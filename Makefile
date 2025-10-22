# Makefile - build and run tests
IVERILOG ?= iverilog
VVP ?= vvp
TCLSH ?= tclsh

SIM_DIR = sim
HW_DIR = hw
TB_DIR = tb

TEST_LIST = $(shell cat $(SIM_DIR)/test_list.txt)

.PHONY: all test clean

all: test

test:
	@echo "Running tests via Tcl script..."
	$(TCLSH) $(SIM_DIR)/run_tests.tcl

compile:
	$(IVERILOG) -g2012 -o $(SIM_DIR)/all_tests.vvp $(HW_DIR)/*.v $(TB_DIR)/*.v

clean:
	rm -rf $(SIM_DIR)/*.vvp $(SIM_DIR)/*_log.txt
