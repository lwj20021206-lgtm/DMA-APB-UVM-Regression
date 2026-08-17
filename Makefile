SHELL := /bin/bash

VCS        ?= vcs
URG        ?= urg
UVM_HOME   ?= /mtklib/soft/verif/Methodology/UVM/uvm/uvm-1.1d/src
UVM_SRC    ?= $(UVM_HOME)
TEST       ?= dma_apb_smoke_test
SEED       ?= 1
VERBOSITY  ?= UVM_LOW
RANDOM_OPS ?= 40
WAVE       ?= 0
FSDB       ?= 0
CM         ?= line+cond+tgl+fsm+branch+assert

ROOT     := $(abspath .)
OUT := $(ROOT)/out

BUILD_VARIANT := normal
ifeq ($(WAVE),1)
BUILD_VARIANT := vpd
endif
ifeq ($(FSDB),1)
BUILD_VARIANT := fsdb
endif

BUILD   := $(OUT)/build/$(BUILD_VARIANT)
SIMV    := $(BUILD)/simv
RUN_ROOT := $(OUT)/runs/$(BUILD_VARIANT)
COV_ROOT := $(OUT)/coverage/$(BUILD_VARIANT)
RUN_ID  := $(TEST)_seed_$(SEED)
RUN_DIR := $(RUN_ROOT)/$(RUN_ID)

DIRECTED_TESTS ?= dma_apb_smoke_test \
                  dma_apb_register_direct_test \
                  dma_apb_init_test \
                  dma_apb_copy_test \
                  dma_apb_interrupt_test \
                  dma_apb_target_wait_test \
                  dma_apb_busy_test \
                  dma_apb_reset_test
RANDOM_SEEDS ?= 1 2 3 4 5

SV_SOURCES := $(shell find . -type f \( -name '*.sv' -o -name '*.v' \) -not -path './out/*')

VCS_FLAGS := -full64 -licqueue -sverilog -timescale=1ns/1ps -debug_pp \
             +define+UVM_OBJECT_MUST_HAVE_CONSTRUCTOR \
             +incdir+$(UVM_SRC)
COMPILE_DEFINES :=
RUN_WAVE_ARGS :=
PLI_FLAGS :=

ifeq ($(WAVE),1)
VCS_FLAGS += +memcbk
COMPILE_DEFINES += +define+ENABLE_VPD
RUN_WAVE_ARGS += +DUMP_VPD +VPD_FILE=waveform.vpd
endif

ifeq ($(FSDB),1)
VCS_FLAGS += +memcbk
COMPILE_DEFINES += +define+ENABLE_FSDB
PLI_FLAGS += -P $(NOVAS_HOME)/share/PLI/VCS/LINUX64/novas.tab \
                $(NOVAS_HOME)/share/PLI/VCS/LINUX64/pli.a
RUN_WAVE_ARGS += +DUMP_FSDB +FSDB_FILE=waveform.fsdb
endif

.PHONY: all compile run run-only regress merge list-tests check-uvm clean help

all: run

help:
	@echo "make compile                              # compile all tests once"
	@echo "make run TEST=dma_apb_copy_test SEED=1   # run one test"
	@echo "make run TEST=dma_apb_busy_test WAVE=1   # run with VPD waveform"
	@echo "make run TEST=dma_apb_copy_test FSDB=1 NOVAS_HOME=/path/to/verdi"
	@echo "make regress                              # directed tests + random seeds + merge"
	@echo "make merge                                # rebuild merged URG report"

list-tests:
	@printf '%s\n' \
	  dma_apb_smoke_test \
	  dma_apb_register_direct_test \
	  dma_apb_init_test \
	  dma_apb_copy_test \
	  dma_apb_interrupt_test \
	  dma_apb_target_wait_test \
	  dma_apb_wait_state_test \
	  dma_apb_busy_test \
	  dma_apb_reset_test \
	  dma_apb_random_test \
	  dma_apb_full_coverage_test \
	  test

check-uvm:
	@test -f "$(UVM_SRC)/uvm.sv" || { \
	  echo "ERROR: $(UVM_SRC)/uvm.sv not found"; \
	  echo "Set UVM_HOME to the UVM-1.1d src directory."; exit 2; }
	@test -f "$(UVM_SRC)/dpi/uvm_dpi.cc" || { \
	  echo "ERROR: $(UVM_SRC)/dpi/uvm_dpi.cc not found"; exit 2; }
	@if [[ "$(FSDB)" == "1" && -z "$(NOVAS_HOME)" ]]; then \
	  echo "ERROR: FSDB=1 requires NOVAS_HOME"; exit 2; fi
	@if [[ "$(WAVE)" == "1" && "$(FSDB)" == "1" ]]; then \
	  echo "ERROR: choose either WAVE=1 (VPD) or FSDB=1"; exit 2; fi

compile: $(SIMV)

$(SIMV): $(SV_SOURCES) filelist.f Makefile | check-uvm
	@mkdir -p "$(BUILD)"
	$(VCS) $(VCS_FLAGS) $(COMPILE_DEFINES) $(PLI_FLAGS) \
	  $(UVM_SRC)/uvm.sv $(UVM_SRC)/dpi/uvm_dpi.cc -CFLAGS -DVCS \
	  -f filelist.f -cm $(CM) -cm_dir $(BUILD)/compile.vdb \
	  -Mdir=$(BUILD)/csrc -o $(SIMV) -l $(BUILD)/compile.log
	@rm -rf "$(RUN_ROOT)" "$(COV_ROOT)"

run: compile run-only

run-only:
	@test -x "$(SIMV)" || { echo "ERROR: run 'make compile' first"; exit 2; }
	@rm -rf "$(RUN_DIR)"
	@mkdir -p "$(RUN_DIR)"
	@cd "$(RUN_DIR)" && "$(SIMV)" \
	  +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) \
	  +UVM_MAX_QUIT_COUNT=1,NO +ntb_random_seed=$(SEED) +vcs+lic+wait \
	  +DMA_RANDOM_OPS=$(RANDOM_OPS) $(RUN_WAVE_ARGS) \
	  -cm $(CM) -cm_name $(RUN_ID) -cm_dir $(RUN_DIR)/coverage.vdb \
	  -l $(RUN_DIR)/sim.log; status=$$?; \
	  "$(ROOT)/scripts/check_run.sh" "$(RUN_DIR)/sim.log" $$status

regress: compile
	@DIRECTED_TESTS="$(DIRECTED_TESTS)" RANDOM_SEEDS="$(RANDOM_SEEDS)" \
	  RANDOM_OPS="$(RANDOM_OPS)" "$(ROOT)/scripts/regress.sh"
	@$(MAKE) --no-print-directory merge

merge: compile
	@mkdir -p "$(COV_ROOT)"
	@test -d "$(BUILD)/compile.vdb" || { \
	  echo "ERROR: compile coverage database is missing"; exit 2; }
	@vdbs=$$(find "$(RUN_ROOT)" -type d -name coverage.vdb \
	  2>/dev/null | sort); \
	  if [[ -z "$$vdbs" ]]; then \
	    echo "ERROR: no per-test coverage.vdb found under $(RUN_ROOT)"; exit 2; \
	  fi; \
	  $(URG) -full64 +urg+lic+wait \
	    -dir "$(BUILD)/compile.vdb" $$vdbs \
	    -dbname "$(COV_ROOT)/merged.vdb" \
	    -report "$(COV_ROOT)/report" \
	    -format both
	@echo "Merged coverage report: $(COV_ROOT)/report/dashboard.html"

clean:
	rm -rf "$(OUT)"
