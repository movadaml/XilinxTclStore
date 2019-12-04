#####################################################################################
#
# generate_hier_access.tcl
# Script created on 11/07/2019 by Raj Klair (Xilinx, Inc.)
#
#####################################################################################
namespace eval ::tclapp::xilinx::projutils {
  namespace export generate_hier_access
}

namespace eval ::tclapp::xilinx::projutils {

proc hbs_init_vars {} {
  # Summary:
  # Argument Usage:
  # Return Value:
  
  variable a_hbs_vars

  set a_hbs_vars(bypass_module)               {}  
  set a_hbs_vars(bypass_file)                 {}  
  set a_hbs_vars(bypass_signal_driver_file)   {}  
  set a_hbs_vars(pseudo_top_testbench)        {}  
  set a_hbs_vars(user_design_testbench)       {}
  set a_hbs_vars(log)                         {}  
 
  set a_hbs_vars(port_attribute)              "hier_bypass_ports"
  set a_hbs_vars(module_attribute)            "hier_bypass_mod"

  set a_hbs_vars(b_bypass_module)               0
  set a_hbs_vars(b_bypass_signal_driver_file) 0
  set a_hbs_vars(b_pseudo_top_testbench)      0
  set a_hbs_vars(b_user_design_testbench)     0
  set a_hbs_vars(b_log)                       0

}

proc generate_hier_access {args} {
  # Summary:
  # Generate sources for hierarchical access simulation
  # Argument Usage: 
  #
  # [-bypass <arg>]: Hierarchical access module name
  # [-driver <arg>]: Signal driver template output file name
  # [-pseudo_top <arg>]: Top-level pseudo testbench module name
  # [-testbench <arg>]: User design testbench module name
  # [-log <arg>]: Simulator log containing hierarchical path information (for non-Vivado users)

  # Return Value:
  # None
  # Categories: simulation, xilinxtclstore
  
  variable a_hbs_vars
  hbs_init_vars

  set a_hbs_vars(options) [split $args " "]
  for {set i 0} {$i < [llength $args]} {incr i} {
    set option [string trim [lindex $args $i]]
    switch $option {
      "-bypass"     { incr i; set a_hbs_vars(bypass_module)             [lindex $args $i]; set a_hbs_vars(b_bypass_module)             1 }
      "-driver"     { incr i; set a_hbs_vars(bypass_signal_driver_file) [lindex $args $i]; set a_hbs_vars(b_bypass_signal_driver_file) 1 }
      "-pseudo_top" { incr i; set a_hbs_vars(pseudo_top_testbench)      [lindex $args $i]; set a_hbs_vars(b_pseudo_top_testbench)      1 }
      "-testbench"  { incr i; set a_hbs_vars(user_design_testbench)     [lindex $args $i]; set a_hbs_vars(b_user_design_testbench)     1 }
      "-log"        { incr i; set a_hbs_vars(log)                       [lindex $args $i]; set a_hbs_vars(b_log)                       1 }
      default {
        if { [regexp {^-} $option] } {
          hbs_print_msg_id "ERROR" "1" "Unknown option '$option', please type 'generate_hier_access -help' for usage info." 
        }
      }
    }
  }

  #
  # command line error
  #
 
  if { (!$a_hbs_vars(b_bypass_module)) || ({} == $a_hbs_vars(bypass_module)) } {
    hbs_print_msg_id "ERROR" "2" "Output bypass file not specified! Please specify the file name using the -file switch."
    return
  }

  if { (!$a_hbs_vars(b_bypass_signal_driver_file)) || ({} == $a_hbs_vars(bypass_signal_driver_file)) } {
    hbs_print_msg_id "ERROR" "3" "Output bypass signal driver file not specified! Please specify the file name using the -driver switch."
    return
  }

  if { (!$a_hbs_vars(b_pseudo_top_testbench)) || ({} == $a_hbs_vars(pseudo_top_testbench)) } {
    set a_hbs_vars(pseudo_top_testbench) "pseudo_top_testbench"
  }

  if { (!$a_hbs_vars(b_user_design_testbench)) || ({} == $a_hbs_vars(user_design_testbench)) } {
    hbs_print_msg_id "ERROR" "4" "Testbench name not specified! Please specify the testbench name using the -user_design_testbench switch."
    return
  }

  #
  # file existence checks
  #
  hbs_generate_bypass

  if { $a_hbs_vars(b_log) } {
    hbs_print_msg_id "STATUS" 7 "Done"
  }
  return 
}

proc hbs_generate_bypass {} {
  # Summary:
  # Argument Usage:
  # Return Value:

  variable a_hbs_vars

  # create bypass file
  set a_hbs_vars(bypass_file) "$a_hbs_vars(bypass_module).sv"
  set fh 0
  if { [file exists $a_hbs_vars(bypass_file)] } {
    if { [catch {file delete -force $a_hbs_vars(bypass_file)} error_msg] } {
      hbs_print_msg_id "ERROR" "8" "Failed to delete file ($a_hbs_vars(bypass_file))"
      return 1
    }
  }
  if { [catch {open $a_hbs_vars(bypass_file) w} fh] } {
    hbs_print_msg_id "ERROR" "9" "Failed to open file to write ($a_hbs_vars(bypass_file))"
    return 1
  } 

  #
  # write top-level pseudo module instantiating test bench
  #
  hbs_write_header $fh

  #
  # write pseudo testbench (top-level testbench in the design for simulating gtm signals)
  #
  if { [hbs_write_pseudo_top_testbench] } {
    return 1
  }

  set log_data {}
  if { $a_hbs_vars(b_log) } {
    set log_data [hbs_extract_hier_paths_from_simulator_log]
  } else {
    set log_data [rdi::get_design_hier_path $a_hbs_vars(port_attribute)] 
  }

  # port list for the driver signal code
  set input_port_list [list]
  set output_port_list [list]
  set instance_port_list [list]

  #
  # write module declaration
  #
  puts $fh "`timescale 1ns/1ps"
  puts $fh "/* Hierarchical access module attribute"
  puts $fh " * --------- DONOT MODIFY -------------*/"
  puts $fh "(* $a_hbs_vars(module_attribute) *)"
  puts -nonewline $fh "module $a_hbs_vars(bypass_module)( "

  if { $a_hbs_vars(b_log) } {
    hbs_print_msg_id "STATUS" 10 "Extracting port information..."
  }
  set port_index 1
  foreach line $log_data {
    set port_count 1
    if { $port_index > 1 } {
      puts -nonewline $fh ","
    }
    set line [string trim $line]
    if { [string length $line] == 0 } { continue }
    #
    # tb.dut_i.gtmWiz_00.gtm_i#in:integer:in1:in_var1 in:integer:in2:in_var2 out:integer:out1:out_var1 out:integer:out2:out_var2
    # 
    set line_v    [split $line {#}]
    set hier_path [lindex $line_v 0]
    set path_spec [lindex $line_v 1]
    set path_spec_v [split $path_spec { }]
    foreach spec $path_spec_v {
      #
      # in:integer:in1:in_var1
      #
      set port_spec [split $spec {:}]
      set port_dir  [lindex $port_spec 0]
      set port_type [lindex $port_spec 1]
      set port_name [lindex $port_spec 2]
      set port_var  [lindex $port_spec 3]
     
      set sig_port "${port_name}__${port_index}" 
      set sig_port_driver "${port_name}_${port_index}" 

      if { "in"  == $port_dir } { lappend input_port_list ${sig_port_driver} }
      if { "out" == $port_dir } { lappend output_port_list ${sig_port_driver} }

      lappend instance_port_list $sig_port_driver

      if { $port_count != 1 } {
        puts -nonewline $fh ", "
      }
      puts -nonewline $fh $sig_port 
      incr port_count
    }
    incr port_index
  }
  puts $fh " );"

  #
  # write input/output ports declaration
  #
  if { $a_hbs_vars(b_log) } {
    # log mode
  } else {
    package require struct::matrix
    struct::matrix mt;
    mt add columns 2;
  }
  set user_tb $a_hbs_vars(user_design_testbench)
  set print_lines_v [list]
  set port_index 1
  foreach line $log_data {
    set port_count 1
    set line [string trim $line]
    if { [string length $line] == 0 } { continue }
    #
    # tb.dut_i.gtmWiz_00.gtm_i#in:integer:in1:in_var1 in:integer:in2:in_var2 out:integer:out1:out_var1 out:integer:out2:out_var2
    # 
    set line_v      [split $line {#}]
    set hier_path   [lindex $line_v 0]
    set hier_path_v [split $hier_path {.}]
    #
    # dut_i.gtmWiz_00.gtm_i#in:integer:in1:in_var1 in:integer:in2:in_var2 out:integer:out1:out_var1 out:integer:out2:out_var2
    # 
    set hier_path   [join [lrange $hier_path_v 1 end] {.}]
    set path_spec   [lindex $line_v 1]
    set path_spec_v [split $path_spec { }]
    if { $port_index > 1 } {
      lappend print_lines_v "\" \" \" \""
    }
    foreach spec $path_spec_v {
      #
      # in:integer:in1:in_var1
      #
      set port_spec [split $spec {:}]
      set port_dir  [lindex $port_spec 0]
      set port_type [lindex $port_spec 1]
      set port_name [lindex $port_spec 2]
      set port_var  [lindex $port_spec 3]
    
      set port_dir_type "input"
      if { "out" == $port_dir } { set port_dir_type "output" }
      set port_col "$port_dir_type $port_type ${port_name}__${port_index};"
      if { "in" == $port_dir } {
        set cmnt_col "// => '$a_hbs_vars(pseudo_top_testbench).${user_tb}_i.${hier_path}.${port_var}'"
      } elseif { "out" == $port_dir } {
        set cmnt_col "// <= '$a_hbs_vars(pseudo_top_testbench).${user_tb}_i.${hier_path}.${port_var}'"
      }
      if { $a_hbs_vars(b_log) } {
        lappend print_lines_v "  $port_col    $cmnt_col"
      } else {
        lappend print_lines_v "\"  $port_col\" \"    $cmnt_col\""
      }
      #puts $fh "  $port_dir_type $port_type ${port_name}__${port_index};   // connected to ${hier_path}.${port_name}"
    }
    incr port_index
  }
  puts $fh ""
  if { $a_hbs_vars(b_log) } {
    foreach p_line $print_lines_v {
      puts $fh $p_line
    }
  } else {
    foreach p_line $print_lines_v {mt add row $p_line}
    puts $fh [mt format 2string]
    mt destroy
  }

  #
  # write DUT bypass driver template code (to be inserted into test bench by the user for driving the input)
  #
  if { [hbs_write_bypass_driver_file input_port_list output_port_list instance_port_list] } {
    return 1
  }

  # 
  # write always block with port assigment
  #

  set port_index 1
  foreach line $log_data {
    set port_count 1
    set line [string trim $line]
    if { [string length $line] == 0 } { continue }
    #
    # tb.dut_i.gtmWiz_00.gtm_i#in:integer:in1:in_var1 in:integer:in2:in_var2 out:integer:out1:out_var1 out:integer:out2:out_var2
    # 
    set line_v      [split $line {#}]
    set hier_path   [lindex $line_v 0]
    set hier_path_v [split $hier_path {.}]
    #
    # dut_i.gtmWiz_00.gtm_i#in:integer:in1:in_var1 in:integer:in2:in_var2 out:integer:out1:out_var1 out:integer:out2:out_var2
    # 
    set hier_path   [join [lrange $hier_path_v 1 end] {.}]
    set path_spec   [lindex $line_v 1]
    set path_spec_v [split $path_spec { }]
    puts $fh ""

    # write for in type
    foreach spec $path_spec_v {
      #
      # in:integer:in1:in_var1
      #
      set port_spec [split $spec {:}]
      set port_dir  [lindex $port_spec 0]
      set port_type [lindex $port_spec 1]
      set port_name [lindex $port_spec 2]
      set port_var  [lindex $port_spec 3]

      set port_id ${port_name}__${port_index}  
      if { "in" == $port_dir } {
        puts $fh "  always @ (${port_id}) begin"
        puts $fh "    $a_hbs_vars(pseudo_top_testbench).${user_tb}_i.${hier_path}.${port_var} = ${port_id};"
        puts $fh "  end"
      }
    }
    puts $fh ""
    # write for out type
    foreach spec $path_spec_v {
      #
      # in:integer:in1:in_var1
      #
      set port_spec [split $spec {:}]
      set port_dir  [lindex $port_spec 0]
      set port_type [lindex $port_spec 1]
      set port_name [lindex $port_spec 2]
      set port_var  [lindex $port_spec 3]

      set port_id ${port_name}__${port_index}  
      if { "out" == $port_dir } {
        puts $fh "  always @ ($a_hbs_vars(pseudo_top_testbench).${user_tb}_i.${hier_path}.${port_var}) begin"
        puts $fh "    ${port_id} = $a_hbs_vars(pseudo_top_testbench).${user_tb}_i.${hier_path}.${port_var};"
        puts $fh "  end"
      }
    }
    incr port_index
  }
  puts $fh ""
  #
  # write module end
  #
  puts $fh "endmodule"
  
  #
  # close bypass file
  #
  close $fh

  if { $a_hbs_vars(b_log) } {
    hbs_print_msg_id "STATUS" 11 "Generated module for setting up bypass hierarchy: $a_hbs_vars(bypass_file)"
  }
}

proc hbs_write_header { fh } {
  # Summary:
  # Argument Usage:
  # Return Value:

  variable a_hbs_vars
  
  puts $fh "//-------------------------------------------------------------------------------------------------------"
  puts $fh "// Copyright (C) 2020 Xilinx, Inc. All rights reserved."
  puts $fh "// Filename: $a_hbs_vars(bypass_file)"
  puts $fh "// Purpose : This is an auto generated bypass module that defines the ports and hierarchical paths for"
  puts $fh "//           propagating the signal values from the top-level testbench to the unisim compoenents. The"
  puts $fh "//           module defines the 'hier_bypass_mod' attribute for identifyng this module to make sure the"
  puts $fh "//           design hierarchy is established for the bypass simulation flow."
  puts $fh "//-------------------------------------------------------------------------------------------------------"
}

proc hbs_write_pseudo_top_testbench {} {
  # Summary:
  # Argument Usage:
  # Return Value:

  variable a_hbs_vars

  set top        $a_hbs_vars(pseudo_top_testbench)
  set tb         $a_hbs_vars(user_design_testbench)

  set fh 0
  set file_name "${top}.sv"
  if { [catch {file delete -force $file_name} error_msg] } {
    hbs_print_msg_id "ERROR" "12" "Failed to delete file ($file_name)"
    return 1
  }
  if { [catch {open $file_name w} fh] } {
    hbs_print_msg_id "ERROR" "13" "Failed to open file to write ($file_name)"
    return 1
  } 
  puts $fh "//-------------------------------------------------------------------------------------------------------"
  puts $fh "// Copyright (C) 2020 Xilinx, Inc. All rights reserved."
  puts $fh "// Filename: ${top}.sv"
  puts $fh "// Purpose : This is an auto generated top level testbench that instantiates the underlying testbench"
  puts $fh "//           or a DUT in the current simulation source hierarchy. The purpose of this testbench source"
  puts $fh "//           is to setup a mixed-language design configuration for calculating the hierarchical path to"
  puts $fh "//           the unisim library components for the purpose of propagating the signal values via the" 
  puts $fh "//           bypass module*. Please verify the design source hierarchy to make sure that this bypass"
  puts $fh "//           module is instantiated correctly."
  puts $fh "//"
  puts $fh "//           *bypass module is a system verilog module that defines the ports and signal propagation" 
  puts $fh "//---------------------------------------------------------------------------------------------------- --"
  puts $fh "`timescale 1ns/1ps"
  puts $fh "module ${top}();"
  puts $fh "  /*"
  puts $fh "   * User design testbench instantiation or a DUT"
  puts $fh "  */"
  puts $fh "  ${tb} ${tb}_i();\n"
  puts $fh "endmodule\n"
  close $fh
  if { $a_hbs_vars(b_log) } {
    hbs_print_msg_id "STATUS" 14 "Generated top-level testbench source for instantiating design testbench '$a_hbs_vars(user_design_testbench)': ${file_name}"
  }

  return 0
}

proc hbs_write_bypass_driver_file { input_ports_arg output_ports_arg instance_ports_arg } {
  # Summary:
  # Argument Usage:
  # Return Value:

  upvar $input_ports_arg input_ports
  upvar $output_ports_arg output_ports
  upvar $instance_ports_arg instance_ports

  variable a_hbs_vars
  set fh 0
  set driver_file $a_hbs_vars(bypass_signal_driver_file)
  if { [catch {file delete -force $driver_file} error_msg] } {
    hbs_print_msg_id "ERROR" "15" "Failed to delete file ($driver_file)"
    return 1
  }
  if { [catch {open $driver_file w} fh] } {
    hbs_print_msg_id "ERROR" "16" "Failed to open file to write ($driver_file)"
    return 1
  }

  puts $fh "-- ------------------------------------------------------------------------------------------------------"
  puts $fh "-- Copyright (C) 2020 Xilinx, Inc. All rights reserved."
  puts $fh "-- Filename: ${driver_file}"
  puts $fh "-- Purpose : This is an auto generated signal driver template code for setting up the input waveform and" 
  puts $fh "--           for instantiating the bypass module in order to propagate the values from the testbench to"
  puts $fh "--           the lower-level unisim components. Please use this code as a reference for setting up the"
  puts $fh "--           input and source hierarchy."  
  puts $fh "-- ------------------------------------------------------------------------------------------------------"
  puts $fh ""
  set entity [file root [file tail ${driver_file}]]
  puts $fh "entity $entity is"
  puts $fh "end entity;"
  puts $fh ""

  #set uniq_in_ports [list]
  #foreach in_port $input_port_list {
  #  if { [lsearch -exact $uniq_in_ports $in_port] == -1 } {
  #    lappend uniq_in_ports $in_port
  #  }
  #}
  #set in_port_str [join $uniq_in_ports {, }]

  #set uniq_out_ports [list]
  #foreach out_port $output_port_list {
  #  if { [lsearch -exact $uniq_out_ports $out_port] == -1 } {
  #    lappend uniq_out_ports $out_port
  #  }
  #}
  #set out_port_str [join $uniq_out_ports {, }]

  set instance_ports_str [join $instance_ports {, }]

  puts $fh "architecture a_${entity} of $entity is"
  foreach in_port $input_ports {
    puts $fh "  signal $in_port : integer;"
  }
  foreach out_port $output_ports {
    puts $fh "  signal $out_port : integer;"
  }
  puts $fh "begin\n"
  puts $fh "-- ************************************************************************************"
  puts $fh "-- INSERT FOLLOWING CODE IN YOUR TESTBENCH SOURCE FILE TO INSTANTIATE THE BYPASS MODULE"
  puts $fh "-- ****************************** COPY START ******************************************"
  puts $fh "  DRIVE_INPUT: process"
  puts $fh "  begin"
  foreach in_port $input_ports {
    puts $fh "    $in_port <= 1 after 0 ns, 3 after 10 ns, 2 after 20 ns, 0 after 30 ns;"
  }
  puts $fh "    wait for 40ns;"
  foreach in_port $input_ports {
    puts $fh "    $in_port <= 3 after 0 ns, 0 after 10 ns, 1 after 20 ns, 2 after 30 ns;"
  }
  puts $fh "    wait for 40ns;"
  foreach in_port $input_ports {
    puts $fh "    $in_port <= 3 after 0 ns, 1 after 10 ns, 0 after 20 ns, 2 after 30 ns;"
  }
  puts $fh "    wait for 40ns;"
  foreach in_port $input_ports {
    puts $fh "    $in_port <= 2 after 0 ns, 3 after 10 ns, 1 after 20 ns, 0 after 30 ns;"
  }
  puts $fh "    wait for 40ns;"
  foreach in_port $input_ports {
    puts $fh "    $in_port <= 0 after 0 ns, 1 after 10 ns, 2 after 20 ns, 3 after 30 ns;"
  }
  puts $fh "    wait;"
  puts $fh "  end process;"
  puts $fh ""
  puts $fh "  HIER_BYPASS : entity work.$a_hbs_vars(bypass_module) port map( $instance_ports_str );"
  puts $fh ""
  puts $fh "-- ****************************** COPY END *********************************************"
  puts $fh ""
  puts $fh "end architecture a_${entity};"
  close $fh

  if { $a_hbs_vars(b_log) } {
    hbs_print_msg_id "STATUS" 17 "Generated signal driver template for instantiating bypass module: ${driver_file}"
  }
  return 0
}

proc hbs_extract_hier_paths_from_simulator_log {} {
  # Summary:
  # Argument Usage:
  # Return Value:

  variable a_hbs_vars
  set log_data [list]
  set tmp_data [list]

  set log_file "$a_hbs_vars(log)"
  set fh_log 0
  if { [catch {open $log_file r} fh_log] } {
    hbs_print_msg_id "ERROR" 18 "Failed to open file to read ($log_file)"
    return 1
  }
  set raw_data [split [read $fh_log] "\n"]
  foreach line $raw_data {
    set line [string trim $line]
    if { [string length $line] == 0 } { continue }
    if { [regexp {^xilinx_hier_bypass_ports} $line] } {
      lappend tmp_data $line
    }
  }
  close $fh_log

  foreach line $tmp_data {
    set line_str [split $line { }]
    set tmp_str  [lindex $line_str 0]
    set hier_path [lindex [split $tmp_str {:}] 1]
    set port_spec_v [lrange $line_str 1 end]
    set port_spec_str [string trim [join $port_spec_v " "]]
    set value "$hier_path#$port_spec_str" 
    lappend log_data $value
  }
  return $log_data
}

proc hbs_print_msg_id { type id str } {
  # Summary:
  # Argument Usage:
  # Return Value:

  if { [catch {package require Vivado}] } {
    set msg "$type: \[generate_hier_access-Tcl-$id\] \"$str\""
    puts $msg
  } else {
    catch {send_msg_id generate_hier_access-Tcl-${id} $type $str}
  }
}

}
if { [catch {package require Vivado}] } {
  namespace import ::tclapp::xilinx::projutils::generate_hier_access
}