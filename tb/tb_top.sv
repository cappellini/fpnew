// Copyright 2022 ETH Zurich

// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Standalone top level wrapper for FPnew mixed precision testbench
// Contributor: Fabio Cappellini <fcappellini@ethz.ch>

// Format for stimuli file:
//
// instr op_mod src_fmt src2_fmt dst_fmt input expected_result
// 
// The instruction is always 5 letters long, unused letters are filled by underscores.
// Valid formats are: FP32, FP16, AL16, FP08, AL08 where AL stands for the respective alternative format.
// 
//
// Example: (see also stimuli.txt)
// VSUM_ 0 FP08 FP08 FP08 6aed7c0daed1ea3260236060 6aed7c56


module tb_top #(
  parameter int WIDTH = 32,
  // Floating-point extensions configuration
  parameter bit C_RVF = 1'b1,  // Is F extension enabled
  parameter bit C_RVD = 1'b0,  // Is D extension enabled - NOT SUPPORTED CURRENTLY

  // Transprecision floating-point extensions configuration
  parameter bit C_XF16 = 1'b1,  // Is half-precision float extension (Xf16) enabled
  parameter bit C_XF16ALT = 1'b1, // Is alternative half-precision float extension (Xf16alt) enabled
  parameter bit C_XF8 = 1'b1,  // Is quarter-precision float extension (Xf8) enabled
  parameter bit C_XF8ALT = 1'b1,  // Is alternative quarter-precision float extension (Xf8alt) enabled

  parameter bit C_XFVEC = 1'b1,  // Is vectorial float extension (Xfvec) enabled

  parameter STIMULI_FILE   = "stimuli.txt" //File for stimuli and expected responses
);

  const time          CLK_PHASE_HI = 5ns;
  const time          CLK_PHASE_LO = 5ns;
  const time          CLK_PERIOD = CLK_PHASE_HI + CLK_PHASE_LO;

  const time          STIM_APPLICATION_DEL = CLK_PERIOD * 0.1;
  const time          RESP_ACQUISITION_DEL = CLK_PERIOD * 0.5;
  const time          RESET_DEL = STIM_APPLICATION_DEL;
  const int           RESET_WAIT_CYCLES = 2;

  // clock and reset for tb
  logic               clk = 'b1;
  logic               rst_n = 'b0;

  // cycle counter
  int unsigned        cycle_cnt_q;

  // clock generation
  initial begin : clock_gen
    forever begin
      #CLK_PHASE_HI clk = 1'b0;
      #CLK_PHASE_LO clk = 1'b1;
    end
  end : clock_gen

  // reset generation
  initial begin : reset_gen
    rst_n = 1'b0;

    // wait a few cycles
    repeat (RESET_WAIT_CYCLES) begin
      @(posedge clk);
    end

    // start running
    #RESET_DEL rst_n = 1'b1;
    if ($test$plusargs("verbose")) $display("reset deasserted", $time);

  end : reset_gen

  // set timing format
  initial begin : timing_format
    $timeformat(-9, 0, "ns", 9);
  end : timing_format

  // abort after n cycles, if we want to
  always_ff @(posedge clk, negedge rst_n) begin
    static int maxcycles = 0; //0 to disable
    if (~rst_n) begin
      cycle_cnt_q <= 0;
    end else begin
      cycle_cnt_q <= cycle_cnt_q + 1;
      if (cycle_cnt_q >= maxcycles && maxcycles != 0) begin
        $fatal(2, "Simulation aborted due to maximum cycle limit");
      end
    end
  end

  // Features (enabled formats, vectors etc.)
  localparam fpnew_pkg::fpu_features_t FPU_FEATURES = '{
  Width:         WIDTH,
  EnableVectors: C_XFVEC,
  EnableNanBox:  1'b1,
  FpFmtMask:     {
    C_RVF, C_RVD, C_XF16, C_XF8, C_XF16ALT, C_XF8ALT
  }, IntFmtMask: {
    C_XFVEC && (C_XF8 || C_XF8ALT), C_XFVEC && (C_XF16 || C_XF16ALT), 1'b1, 1'b0
  }};

  localparam fpnew_pkg::fpu_implementation_t FPU_IMPLEMENTATION =
  '{
      PipeRegs: // FMA Block
                '{
                  '{  2, // FP32
                      2, // FP64
                      1, // FP16
                      1, // FP8
                      1, // FP16alt
                      1  // FP8alt
                    },
                  '{default: 1},   // DIVSQRT
                  '{default: 1},   // NONCOMP
                  '{default: 1},   // CONV
                  '{default: 2}    // DOTP
                  },
      UnitTypes: '{'{default: fpnew_pkg::MERGED},  // FMA
                  '{default: fpnew_pkg::DISABLED}, // DIVSQRT
                  '{default: fpnew_pkg::PARALLEL}, // NONCOMP
                  '{default: fpnew_pkg::MERGED},   // CONV
                  '{default: fpnew_pkg::MERGED}},  // DOTP
      PipeConfig: fpnew_pkg::BEFORE
  };


  logic [2:0][WIDTH-1:0]          fpu_operands;
  fpnew_pkg::roundmode_e          fpu_rnd_mode;
  fpnew_pkg::operation_e          fpu_operation;
  logic                           fpu_op_mod;
  fpnew_pkg::fp_format_e          fpu_src_fmt;
  fpnew_pkg::fp_format_e          fpu_src2_fmt;
  fpnew_pkg::fp_format_e          fpu_dst_fmt;

  // FPnew signals
  //fpu_tag_t                        fpu_tag_in;
  logic                            fpu_tag_out;
  logic                            fpu_in_valid;
  logic                            fpu_in_ready;
  logic                            fpu_out_valid;
  logic                            fpu_out_ready;
  logic                [WIDTH-1:0] fpu_result;
  logic                            fpu_busy;
  fpnew_pkg::status_t              fpu_status;


  // buffer for results
  logic [1:0]  [WIDTH-1:0] expected_result_d, expected_result_q;
  logic [1:0][3*WIDTH-1:0] fpu_operands_d, fpu_operands_q;

  assign fpu_out_ready = fpu_out_valid; //always accept outgoing data


  localparam STIMULI_MODE = 1;  //set to 0 to run in manual mode
  //apply stimuli and compare with expected result
  initial begin : stimuli_application
    if(STIMULI_MODE) begin
      int stimuli_file;
      int scan_status;

      int result_buffer_index;

      string operation;
      string src_fmt;
      string src2_fmt;
      string dst_fmt;
      string comment;


      stimuli_file = $fopen(STIMULI_FILE, "r");

      if(stimuli_file) $display("File %s openend.", STIMULI_FILE);
      else $fatal("Failed to open %s.", STIMULI_FILE);
      scan_status = $fgets(comment, stimuli_file); //read first line, is then ignored

      fpu_in_valid = 1'b0;

      while(!$feof(stimuli_file)) begin
        scan_status = $fscanf(stimuli_file, "%s %b %s %s %s %x %x\n", operation, fpu_op_mod, src_fmt, src2_fmt, dst_fmt, fpu_operands, expected_result_d[0]);
        if(!scan_status) $fatal("Could not read line.");

        fpu_operation = string_to_fpu_operation(operation); 
        fpu_src_fmt   = string_to_fp_format(src_fmt);
        fpu_src2_fmt  = string_to_fp_format(src2_fmt); 
        fpu_dst_fmt   = string_to_fp_format(dst_fmt);  

        fpu_in_valid = 1'b1;

        //wait 1 cycle + acquisition delay
        @(posedge clk);
        #RESP_ACQUISITION_DEL;

        if(fpu_result !== expected_result_q[1]) begin
          //Check if actual and expected result are both NaN (Mantissa all ones), only works for fp32 output
          if((& expected_result_q[1][30:23]) && (& fpu_result[30:23])) begin
            //$warning("Different NaN, expected: %x, got: %x, input: %x", exp_result, fpu_result, fpu_operands);
          end else begin
            $error("Error, expected: %x, got: %x, input: %x.", expected_result_q[1], fpu_result, fpu_operands_q[1]);
          end
        end
      end

      $fclose(stimuli_file);
      $display("Tests finished.");
      $finish;
    end else begin
      $warning("Running in manual mode, no errors expected.");
      //Manual Mode starts here:

      fpu_operands = 'h FF47FF6aFFFFFFFF6bf8fba6;
      fpu_op_mod = 1'b0;
      fpu_operation = fpnew_pkg::VSUM;
      fpu_src_fmt   = fpnew_pkg::FP8;
      fpu_src2_fmt  = fpnew_pkg::FP8;
      fpu_dst_fmt   = fpnew_pkg::FP8ALT;

      fpu_in_valid = 1'b1;

      repeat (10) begin
        @(posedge clk);
      end
      #RESP_ACQUISITION_DEL;
      $display("Got: %x", fpu_result);
      $finish;
    end
  end

  assign expected_result_d[1] = expected_result_q[0];
  assign fpu_operands_d[1] = fpu_operands_q[0];
  assign fpu_operands_d[0] = fpu_operands;
  always_ff @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
      expected_result_q[0] <= 0;
      expected_result_q[1] <= 0;
      fpu_operands_q[0] <= 0;
      fpu_operands_q[1] <= 0;
    end else begin
      expected_result_q[0] <= expected_result_d[0];
      expected_result_q[1] <= expected_result_d[1];
      fpu_operands_q[0] <= fpu_operands_d[0];
      fpu_operands_q[1] <= fpu_operands_d[1];

    end
  end

  fpnew_top #(
      .Features      (FPU_FEATURES),
      .Implementation(FPU_IMPLEMENTATION),
      .TagType       (logic)
  ) i_fpnew_bulk (
      .clk_i         (clk),
      .rst_ni        (rst_n),
      .operands_i    (fpu_operands),
      .rnd_mode_i    (fpnew_pkg::RNE),
      .op_i          (fpu_operation),
      .op_mod_i      (fpu_op_mod),
      .src_fmt_i     (fpu_src_fmt),
      .src2_fmt_i    (fpu_src2_fmt), 
      .dst_fmt_i     (fpu_dst_fmt),
      .int_fmt_i     (fpnew_pkg::INT32),
      .vectorial_op_i(1'b1),
      .tag_i         (fpu_tag_in),
      .in_valid_i    (fpu_in_valid),
      .in_ready_o    (fpu_in_ready),
      .flush_i       (1'b0),
      .result_o      (fpu_result),
      .status_o      (fpu_status),
      .tag_o         (),
      .out_valid_o   (fpu_out_valid),
      .out_ready_i   (fpu_out_ready),
      .busy_o        (fpu_busy)
  );

  function automatic fpnew_pkg::fp_format_e string_to_fp_format(string inp_format);
    fpnew_pkg::fp_format_e res;
    case(inp_format)
      "FP32":    res = fpnew_pkg::FP32;
      "FP64":    res = fpnew_pkg::FP64;
      "FP16":    res = fpnew_pkg::FP16;
      "AL16":    res = fpnew_pkg::FP16ALT;
      "FP08":    res = fpnew_pkg::FP8;
      "AL08":    res = fpnew_pkg::FP8ALT;
      default:   res = fpnew_pkg::FP32;
    endcase
    return res;
  endfunction

  function automatic fpnew_pkg::operation_e string_to_fpu_operation(string inp_operation);
  fpnew_pkg::operation_e res;
  case(inp_operation)
    "SDOTP":     res = fpnew_pkg::SDOTP;
    "EXVSU":     res = fpnew_pkg::EXVSUM;  
    "VSUM_":     res = fpnew_pkg::VSUM;   
    "FMADD":     res = fpnew_pkg::FMADD;   
    "FNMSB":     res = fpnew_pkg::FNMSUB;  
    "ADD__":     res = fpnew_pkg::ADD;   
    "MUL__":     res = fpnew_pkg::MUL;     
    "DIV__":     res = fpnew_pkg::DIV;     
    "SQRT_":     res = fpnew_pkg::SQRT;    
    "SGNJ_":     res = fpnew_pkg::SGNJ;    
    "MINMA":     res = fpnew_pkg::MINMAX;  
    "CMP__":     res = fpnew_pkg::CMP;    
    "CLASS":     res = fpnew_pkg::CLASSIFY;
    "F2F__":     res = fpnew_pkg::F2F;
    "F2I__":     res = fpnew_pkg::F2I;
    "I2F__":     res = fpnew_pkg::I2F;
    "CPKAB":     res = fpnew_pkg::CPKAB;
    "CPKCD":     res = fpnew_pkg::CPKCD;
    default:     res = fpnew_pkg::SDOTP;
  endcase
  return res;
endfunction

endmodule  // tb_top