extends SceneTree
## A7: runs every test listed in tools/tests.cfg, each in its own fresh copy of Godot, and prints
## a table at the end. Not part of the game.
##   godot --headless --path . --script tools/run_all.gd
##   godot --headless --path . --script tools/run_all.gd -- --quick       (skip the slow co-op tests)
##   godot --headless --path . --script tools/run_all.gd -- --only t5,d9  (just these; also "manual" ones)
##   godot --headless --path . --script tools/run_all.gd -- --all         (also the "manual" ones)
##   godot --headless --path . --script tools/run_all.gd -- --no-window   (skip tests that need a window)
## Each test's whole output goes to tools/test_logs/<name>.log (ignored by git).
## A test FAILS if: it prints a line starting with "FAIL" or "RESULT: FAILED", shows a script /
## parse error, quits with an error code, crashes, never prints its end line, or runs too long.
## The runner quits with code 1 if any test failed - that is what GitHub's ✅ / ❌ reads.

const LIST := "res://tools/tests.cfg"
const LOG_DIR := "res://tools/test_logs"
const QUICK_SKIP := ["test_coop", "test_net3_coop", "test_benchmark"]
const ERROR_MARKS := ["SCRIPT ERROR", "Parse Error", "Failed to load script", "Invalid call", "Invalid access"]

var _results: Array[Dictionary] = []
var _count_re := RegEx.create_from_string("(\\d+) (failure|failed|fail)")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var opts := _read_options()
	var tests := _read_list()
	if tests.is_empty():
		printerr("run_all: no tests found in ", LIST)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
	var can_window := _has_display()
	var started := Time.get_ticks_msec()
	var chosen: Array[Dictionary] = []
	for t: Dictionary in tests:
		var why := _skip_reason(t, opts, can_window)
		if why == "":
			chosen.append(t)
		elif why != "not in --only":
			_results.append({name = t.name, status = "SKIP", secs = 0.0, note = why})
	if chosen.is_empty():
		printerr("run_all: nothing to run (check --only)")
		quit(1)
		return
	print("run_all: %d tests" % chosen.size())
	var i := 0
	for t: Dictionary in chosen:
		i += 1
		print("[%d/%d] %s ..." % [i, chosen.size(), t.name])
		var r: Dictionary = await _run_one(t)
		_results.append(r)
		print("        %s  %.0f s%s" % [r.status, r.secs, ("   " + r.note) if r.note != "" else ""])
		if r.status != "OK":
			_show_failure(r)
	_print_table((Time.get_ticks_msec() - started) / 1000.0)
	var failed := _results.filter(func(r: Dictionary) -> bool: return r.status == "FAILED").size()
	quit(1 if failed > 0 else 0)


# --- Options and the list -----------------------------------------------------------------

func _read_options() -> Dictionary:
	var opts := {quick = false, all = false, no_window = false, only = []}
	var args := OS.get_cmdline_user_args()
	var k := 0
	while k < args.size():
		var a: String = args[k]
		if a == "--quick":
			opts.quick = true
		elif a == "--all":
			opts.all = true
		elif a == "--no-window":
			opts.no_window = true
		elif a == "--only" and k + 1 < args.size():
			k += 1
			opts.only = _short_names(args[k])
		elif a.begins_with("--only="):
			opts.only = _short_names(a.substr(7))
		else:
			printerr("run_all: unknown option ", a)
		k += 1
	return opts


## "t5,d9" or "test_t5.gd" -> ["t5", "d9"] (compared without "test_" / ".gd").
func _short_names(text: String) -> Array:
	var out := []
	for s in text.split(",", false):
		out.append(_short(s.strip_edges()))
	return out


func _short(name: String) -> String:
	return name.get_file().trim_suffix(".gd").trim_prefix("test_")


func _read_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f := FileAccess.open(LIST, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var t := {script = "", name = "", limit = 180.0, window = false, manual = false,
				end = "RESULT:", args = PackedStringArray()}
		# end=TEXT may hold spaces, so take it off the line first.
		var end_at := line.find("end=")
		if end_at >= 0:
			t.end = line.substr(end_at + 4).strip_edges()
			line = line.substr(0, end_at).strip_edges()
		var parts := line.split(" ", false)
		t.script = parts[0]
		t.name = parts[0].trim_suffix(".gd")
		if parts.size() > 1 and parts[1].is_valid_float():
			t.limit = parts[1].to_float()
		for p in parts.slice(2):
			if p == "window":
				t.window = true
			elif p == "manual":
				t.manual = true
			elif p.begins_with("args="):
				t.args = p.substr(5).split(",", false)
		out.append(t)
	return out


func _skip_reason(t: Dictionary, opts: Dictionary, can_window: bool) -> String:
	if not opts.only.is_empty():
		if not opts.only.has(_short(t.name)):
			return "not in --only"
	elif t.manual and not opts.all:
		return "manual (use --all)"
	elif opts.quick and QUICK_SKIP.has(t.name):
		return "--quick"
	if t.window and (opts.no_window or not can_window):
		return "needs a window"
	return ""


func _has_display() -> bool:
	if OS.get_name() in ["Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD"]:
		return OS.get_environment("DISPLAY") != "" or OS.get_environment("WAYLAND_DISPLAY") != ""
	return true


# --- Running one test ---------------------------------------------------------------------

func _run_one(t: Dictionary) -> Dictionary:
	var args := PackedStringArray()
	if not t.window:
		args.append("--headless")
	args.append_array(["--path", ProjectSettings.globalize_path("res://"),
			"--script", "tools/run.gd", "--", "tools/" + t.script])
	args.append_array(t.args)
	var started := Time.get_ticks_msec()
	var proc := OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if proc.is_empty():
		return {name = t.name, status = "FAILED", secs = 0.0, note = "could not start Godot", log = ""}
	var out: FileAccess = proc.stdio
	var err: FileAccess = proc.stderr
	var pid: int = proc.pid
	var text := ""
	var timed_out := false
	var error_seen_at := -1
	while true:
		text += _drain(out) + _drain(err)
		if not OS.is_process_running(pid):
			break
		if (Time.get_ticks_msec() - started) / 1000.0 > t.limit:
			timed_out = true
			OS.kill(pid)
			break
		# A script error usually leaves the test waiting for ever: stop it after 3 s, not at the limit.
		if error_seen_at < 0 and text.contains("SCRIPT ERROR"):
			error_seen_at = Time.get_ticks_msec()
		if error_seen_at >= 0 and Time.get_ticks_msec() - error_seen_at > 3000:
			OS.kill(pid)
			break
		await create_timer(0.05).timeout
	await create_timer(0.1).timeout # what was written just before the end
	text += _drain(out) + _drain(err)
	var code := -1 if timed_out else OS.get_process_exit_code(pid)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var log_path := LOG_DIR.path_join(t.name + ".log")
	var lf := FileAccess.open(log_path, FileAccess.WRITE)
	if lf:
		lf.store_string(text)
	var r := {name = t.name, status = "OK", secs = secs, note = "", log = text,
			log_path = ProjectSettings.globalize_path(log_path)}
	var problems := _judge(text, t.end)
	if timed_out:
		problems.insert(0, "took longer than %d s" % int(t.limit))
	elif code != 0:
		problems.insert(0, "quit with code %d" % code)
	if not problems.is_empty():
		r.status = "FAILED"
		r.note = problems[0]
	return r


func _drain(f: FileAccess) -> String:
	if f == null:
		return ""
	var buf := PackedByteArray()
	while true:
		var part := f.get_buffer(65536)
		if part.is_empty():
			break
		buf.append_array(part)
	return buf.get_string_from_utf8()


func _judge(text: String, end_mark: String) -> PackedStringArray:
	var problems := PackedStringArray()
	var fails := 0          # lines "FAIL  ..."
	var reported := false   # the test's own summary says something failed
	var reached_end := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("FAIL ") or line.begins_with("FAIL\t") or line == "FAIL":
			fails += 1
		if line.begins_with("RESULT: FAILED") or line.contains("BROKEN"):
			reported = true
		for m: String in ERROR_MARKS:
			if line.contains(m):
				problems.append("error: " + line.left(120))
		if line.begins_with(end_mark):
			reached_end = true
			# "TEST T5 DONE: 2 failure(s)", "RESULT: OK (0 failed)": a count above 0 is a failure too.
			var m := _count_re.search(line)
			if m and m.get_string(1).to_int() > 0:
				reported = true
	if fails > 0:
		problems.insert(0, "%d failed check(s)" % fails)
	elif reported:
		problems.insert(0, "the test reports a failure")
	if not reached_end:
		problems.append("never printed \"%s\" (stopped early?)" % end_mark)
	return problems


# --- Output -------------------------------------------------------------------------------

func _show_failure(r: Dictionary) -> void:
	var lines: PackedStringArray = (r.log as String).split("\n")
	var shown := 0
	for line in lines:
		var s := line.strip_edges()
		if s.begins_with("FAIL") or s.contains("BROKEN") \
				or ERROR_MARKS.any(func(m: String) -> bool: return s.contains(m)):
			print("          | ", line)
			shown += 1
			if shown >= 20:
				break
	print("          last lines:")
	for line in lines.slice(maxi(0, lines.size() - 12)):
		print("          | ", line)
	print("          whole output: ", r.get("log_path", ""))


func _print_table(total_secs: float) -> void:
	var ok := 0
	var failed := 0
	var skipped := 0
	print("")
	print("=== Test results ===")
	for r: Dictionary in _results:
		match r.status:
			"OK": ok += 1
			"FAILED": failed += 1
			_: skipped += 1
		if r.status == "SKIP":
			continue
		print("%-7s %-22s %5.0f s  %s" % [r.status, r.name, r.secs, r.note])
	print("--------------------")
	print("%d OK, %d FAILED, %d skipped   (%.1f min)" % [ok, failed, skipped, total_secs / 60.0])
	if failed > 0:
		print("TESTS FAILED: " + ", ".join(_results.filter(
				func(r: Dictionary) -> bool: return r.status == "FAILED").map(
				func(r: Dictionary) -> String: return r.name)))
	else:
		print("ALL TESTS OK")
