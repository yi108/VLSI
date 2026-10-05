# ----------------------------------------------------------------------
# VSD HW2 - local simulation Makefile (Icarus Verilog based).
#
# NOTE: the course provides its own Makefile / testbench / prog_lib on the
# course server ("You shouldn't modify it"). This Makefile is a stand-in so
# the design can be regression-tested anywhere:
#   make rtl0        RTL simulation of prog0
#   make rtl1        RTL simulation of prog1
#   make rtl_all     all programs
#   make fpu         FPU random-vector unit test
#   make rtl0 FSDB=1 dump waveform (VCD)
#   make clean
# On the course server, drop src/ into the provided VSD2026_HW2 environment
# and use the official "make rtl0 ... make syn0" flow unchanged.
# ----------------------------------------------------------------------

SRC   := $(wildcard src/*.sv)
TB    := sim/top_tb.sv
PROGS := 0 1
SEED  ?= 1
IVFLAGS := -g2012

ifdef FSDB
IVFLAGS += -DFSDB
endif

.PHONY: all rtl_all fpu clean check count_lines $(addprefix rtl,$(PROGS))

all: rtl_all

define RTL_RULE
rtl$(1): build/sim$(1)
	@if [ -f sim/prog$(1)/data$(1).hex ]; then DATA="+data=sim/prog$(1)/data$(1).hex"; else DATA=""; fi; \
	vvp build/sim$(1) +seed=$(SEED) +prog=sim/prog$(1)/prog$(1).hex $$$$DATA \
	    +gold_x=sim/prog$(1)/golden/golden_xreg.hex \
	    +gold_f=sim/prog$(1)/golden/golden_freg.hex \
	    +gold_d=sim/prog$(1)/golden/golden_dmem.hex

build/sim$(1): $(SRC) $(TB) sim/prog$(1)/prog$(1).hex sim/prog$(1)/golden/golden_xreg.hex
	@mkdir -p build
	iverilog $(IVFLAGS) -o $$@ $(TB) $(SRC)

sim/prog$(1)/prog$(1).hex: sim/prog$(1)/prog$(1).s tools/asm.py
	python3 tools/asm.py $$< $$@

sim/prog$(1)/golden/golden_xreg.hex: sim/prog$(1)/prog$(1).hex tools/iss.py
	@mkdir -p sim/prog$(1)/golden
	python3 tools/iss.py sim/prog$(1)/prog$(1).hex sim/prog$(1)/data$(1).hex sim/prog$(1)/golden
endef

$(foreach p,$(PROGS),$(eval $(call RTL_RULE,$(p))))

rtl_all: $(addprefix rtl,$(PROGS))

fpu: build/fp_vectors.hex
	@mkdir -p build
	iverilog $(IVFLAGS) -o build/fputb sim/fpu_tb.sv src/fpu.sv
	vvp build/fputb +vec=build/fp_vectors.hex

build/fp_vectors.hex: tools/gen_fp_vectors.py
	@mkdir -p build
	python3 tools/gen_fp_vectors.py $@ 30000

count_lines:
	@wc -l src/*.sv

check:
	@test -d src && test -d sim && test -d script && echo "file structure OK"

clean:
	rm -rf build *.vcd
