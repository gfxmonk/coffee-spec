fs: require 'fs'
sys: require "sys"
debug: sys.debug
puts: sys.puts
term: require "../lib/term"
assert: require "assert"

helpers: {
	# (blatantly stolen from coffeescript-proper)
	# Merge objects, returning a fresh copy with attributes from both sides.
	# Used every time `BaseNode#compile` is called, to allow properties in the
	# options hash to propagate down the tree without polluting other branches.
	merge: ((options, overrides) ->
		fresh: {}
		(fresh[key]: val) for key, val of options
		(fresh[key]: val) for key, val of overrides if overrides
		fresh),

	# Extend a source object with the properties of another object (shallow copy).
	# We use this to simulate Node's deprecated `process.mixin`
	extend: ((object, properties) ->
		(object[key]: val) for key, val of properties),
}
CoffeeScript: require("../lib/coffee-script")

term: {
	red: '\033[0;31m',
	green: '\033[0;32m',
	normal: '\033[0m',
}

test_exports: {}

#TODO: some env vars for this?
LIKELY_COFFEESCRIPT_PATHS: []
LIKELY_LIB_PATHS: ['../lib','lib']

tests: []
errors: []
succeeded: 0
failed: 0
unit: "tests"
start_time: new Date()

add_error: (err) ->
  errors.push(err)
  failed += 1

# remove all node.js and lib/spec.js lines from stack trace
cleanup_stack: (stack) ->
  stack: stack.replace /\n^.*lib\/spec\.js:\d+:\d+\)$/gm, ''
  stack: stack.replace /\n^\s+at node\.js:\d+:\d+$/gm, ''
  stack

# Output a detailed report on all failing tests
exports.report: report: (verbose) ->
  puts "\n-------------------------" if failed and verbose
  for error in errors
    [description, stack]: error
    puts "${term.red}FAILED: $description${term.normal}"
    puts stack
  return failed

# Summarize entire test run
exports.summarize: summarize: ->
  time_elapsed: ((new Date() - start_time) / 1000).toFixed(2)
  message: "passed ${succeeded} ${unit} in $time_elapsed seconds${term.normal}"
  puts ""
  puts(if failed then "${term.red}FAILED ${failed} and $message" else "${term.green}$message")
  
# Runs all tests that have not yet been run
# (note that this method can be called mutliple times, and it
# will only run the new tests that have not yet been run)
exports.run_tests: run_tests: (verbose) ->
  for test in tests
    [desc, body] = test
    sys.print " - " + desc + " ... " if verbose
    try
      body()
      succeeded += 1
      sys.puts "${term.green}ok${term.normal}" if verbose
    catch e
      sys.puts "${term.red}failed${term.normal}" if verbose
      add_error [desc, cleanup_stack(e.stack)]
  tests: []

# Run all defined tests, report and
# exit with the number of failed tests
exports.run_standalone: run_standalone: (verbose) ->
  run_tests(verbose)
  report(verbose)
  process.exit(failed)

# Add tests from a file and immediately run them
exports.run_file: run_file: (file, verbose) ->
  print_file file if verbose
  code: fs.readFileSync file
  CoffeeScript.run code, {source: file}
  run_tests(verbose)

print_file: (file) ->
  puts "\n" + file + ":"

exports.compile_and_run_file: compile_and_run_file: (dir, file, temp_path, verbose, cb) ->
  output_file: file.replace /\.coffee$/, '.js'
  file_path: "$dir/$file"
  output_path: "$temp_path/$output_file"
  prelude: "require('cofee-spec').autorun(global, ${verbose});"
  input_code: prelude + fs.readFileSync("$dir/$file")
  compiled: CoffeeScript.compile input_code, {source:file_path}
  fs.writeFileSync(output_path, compiled)
  exec "node '$output_path'", (err, stdout, stderr) ->
    print_file(file_path) if verbose
    if err
      failed += 1
    else
      succeeded += 1
    puts stdout if stdout
    puts stderr if stderr
    cb()

# Run all tests in a given directory
exports.run: (dir, options) ->
  filter: options.filter
  verbose: options.verbose
  temp_dir: options.temp_dir
  do_end: ->
    report(verbose)
    summarize()
    process.exit(failed)

  do_run: ->
    files: fs.readdirSync dir
    iterate: ->
      if files.length == 0
        return do_end()
      file: files.shift()
      return iterate() unless file.match(/\.coffee$/i)
      return iterate() if filter and file.search(filter) == -1
      if options.compile
        unit: "test files"
        compile_and_run_file dir, file, temp_dir, options.verbose, iterate
      else
        run_file("$dir/$file", options.verbose)
        iterate()
    iterate()

  if options.compile
    mkdir: process.createChildProcess 'mkdir', ['-p', temp_dir]
    mkdir.addListener 'exit', do_run
  else
    helpers.extend global, global_scope
    do_run()

# DSL-land
current_describe: null
test_exports.describe: describe: (desc, body) ->
  old_describe: current_describe
  if current_describe
    current_describe += ' ' + desc
  else
    current_describe: desc
  body()
  current_describe: old_describe

test_exports.it: it: (desc, body) ->
  if not (typeof body == 'function')
    throw new Error("not a function: " + body)
  if current_describe?
    desc = current_describe + ' ' + desc
  tests.push([desc, body])

exports.autorun: (_globals, verbose) ->
  helpers.extend _globals, global_scope
  setTimeout(( -> run_standalone(verbose)), 0)

global_scope: helpers.merge(test_exports, assert)
