# sim/run_tests.tcl
# Tcl script to compile and run tests with iverilog and vvp, collect logs and report PASS/FAIL.

set tests_file "sim/test_list.txt"
set sim_dir "sim"
set tb_dir "tb"
set hw_dir "hw"
set vvp_flags ""
set iverilog "iverilog"
set vvp "vvp"

# Create sim dir
file mkdir $sim_dir

# read tests
set fp [open $tests_file r]
set tests [split [read $fp] "\n"]
close $fp

set pass_count 0
set fail_count 0

puts "Running tests..."
foreach t $tests {
  if {$t == ""} continue
  set logfile "${sim_dir}/${t}_log.txt"
  set vvpfile "${sim_dir}/${t}.vvp"
  # compile command: include hw and tb
  set cmd_compile "$iverilog -g2012 -o $vvpfile $hw_dir/*.v $tb_dir/${t}.v"
  puts "Compiling $t..."
  if {[catch {exec {*}[split $cmd_compile " "]} compile_out]} {
    puts "Compile failed for $t: $compile_out"
    incr fail_count
    continue
  }
  # run
  puts "Running $t..."
  if {[catch {exec {*}[split $vvp " " ] $vvpfile} simout]} {
    # capture stdout/stderr into logfile
    set f [open $logfile w]
    puts $f $simout
    close $f
  } else {
    # vvp printed nothing? capture using redirect
    # run and capture
    set simout [exec {*}[split $vvp " "] $vvpfile]
    set f [open $logfile w]
    puts $f $simout
    close $f
  }

  # if logfile contains "FAIL", mark fail
  set f2 [open $logfile r]
  set content [read $f2]
  close $f2
  if {[string match "*FAIL*" $content]} {
    puts "$t... FAIL (see $logfile)"
    incr fail_count
  } else {
    puts "$t... PASS"
    incr pass_count
  }
}

puts ""
puts "Summary: $pass_count PASS, $fail_count FAIL"
