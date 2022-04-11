# Copyright 2022 ETH Zurich
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
# REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
# AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
# INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
# OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.

# Author: Fabio Cappellini (fcappellini@ethz.ch)
#
# Description: Makefile for running the FPnew mixed precision testbench
# 
# Use 'make' to run simulation or 'make gui' to also start the GUI

MAKE			= make

# vsim configuration
VVERSION                = "10.7b"

VLIB			= vlib-$(VVERSION)
VWORK			= work

VLOG			= vlog-$(VVERSION)
VLOG_FLAGS		= -pedanticerrors -suppress 2577 -suppress 2583
VLOG_LOG                = vloggy

VOPT			= vopt-$(VVERSION)
VOPT_FLAGS		= -debugdb -fsmdebug -pedanticerrors +acc #=mnprft

VSIM			= vsim-$(VVERSION)
VSIM_HOME               = /usr/pack/modelsim-$(VVERSION)-kgf/questasim
VSIM_FLAGS              =  # user defined
ALL_VSIM_FLAGS		= $(VSIM_FLAGS)
VSIM_DEBUG_FLAGS	= -debugdb
VSIM_GUI_FLAGS          = -gui -debugdb -do wave.do
VSIM_SCRIPT             = vsim.tcl


export RTLSRC_HOME	:= ../src
RTLSRC		        := $(wildcard $(RTLSRC_HOME)/*.sv)

RTLSRC_TB_TOP		:= tb_top.sv
RTLSRC_TB		:= $(wildcard *.sv)

RTLSRC_PKG	:= $(RTLSRC_HOME)/fpnew_pkg.sv

RTLSRC_VLOG_TB_TOP	:= $(basename $(notdir $(RTLSRC_TB_TOP)))
RTLSRC_VOPT_TB_TOP	:= $(addsuffix _vopt, $(RTLSRC_VLOG_TB_TOP))

INC = $(RTLSRC_HOME)/common_cells/include

INC_SRC = $(wildcard $(RTLSRC_HOME)/common_cells/src/*.sv)

INC_SRC_FLTR = $(filter-out $(RTLSRC_HOME)/common_cells/src/ecc_decode.sv, $(INC_SRC))

CMN_CELL_SRC = $(RTLSRC_HOME)/common_cells/src

PKG_SRC = $(wildcard $(CMN_CELL_SRC)/*pkg.sv)

# assume vsim if no target chosen
.DEFAULT_GOAL := vsim-run

.PHONY: gui
gui: vsim-run-gui

.lib-rtl:
	$(VLIB) $(VWORK)
	touch .lib-rtl

# rebuild if we change some sourcefile
.build-rtl: .lib-rtl $(RTLSRC_PKG) $(PKG_SRC) $(INC_SRC_FLTR) $(RTLSRC) $(RTLSRC_TB_TOP)
	$(VLOG) -work $(VWORK) +incdir+$(INC) $(VLOG_FLAGS) \
	$(RTLSRC_PKG) $(PKG_SRC) $(INC_SRC_FLTR) $(RTLSRC) $(RTLSRC_TB_TOP)
	touch .build-rtl

.PHONY: vsim-all
vsim-all: .opt-rtl

.opt-rtl: .build-rtl
	$(VOPT) -work $(VWORK) $(VOPT_FLAGS) $(RTLSRC_VLOG_TB_TOP) -o \
	$(RTLSRC_VOPT_TB_TOP)
	touch .opt-rtl

# run tb and exit
.PHONY: vsim-run
vsim-run: ALL_VSIM_FLAGS += -c
vsim-run: vsim-all
	$(VSIM) -work $(VWORK) $(ALL_VSIM_FLAGS) \
	$(RTLSRC_VOPT_TB_TOP) -do 'source $(VSIM_SCRIPT); exit -f'


# run tb with simulator gui
.PHONY: vsim-run-gui
vsim-run-gui: ALL_VSIM_FLAGS += $(VSIM_GUI_FLAGS)
vsim-run-gui: vsim-all
	$(VSIM) -work $(VWORK) $(ALL_VSIM_FLAGS) \
	$(RTLSRC_VOPT_TB_TOP) -do $(VSIM_SCRIPT)


.PHONY: tb-clean
tb-clean:
	if [ -d $(VWORK) ]; then rm -r $(VWORK); fi
	rm -f transcript vsim.wlf vsim.dbg \
	.build-rtl .opt-rtl .lib-rtl *.vcd objdump


# general targets
.PHONY: clean
clean: tb-clean