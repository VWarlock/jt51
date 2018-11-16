/*  This file is part of JT51.

    JT51 is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT51 is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT51.  If not, see <http://www.gnu.org/licenses/>.
    
    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 27-10-2016
    */

`timescale 1ns / 1ps

module jt51_mmr(
    input           rst,
    input           clk,
    input           clk_en,     // clock enable for FM modules
    input   [7:0]   d_in,
    input           write,
    input           a0,
    output  reg     busy,
    
    // CT
    output  reg     ct1,
    output  reg     ct2,
    
    // Noise
    output  reg         ne,
    output  reg [4:0]   nfrq,

    // LFO
    output  reg [7:0]   lfo_freq,
    output  reg [1:0]   lfo_w,
    output  reg [6:0]   lfo_amd,    
    output  reg [6:0]   lfo_pmd,
    output  reg         lfo_rst,
    // Timers
    output  reg [9:0]   value_A,
    output  reg [7:0]   value_B,
    output  reg         load_A,
    output  reg         load_B,
    output  reg         enable_irq_A,
    output  reg         enable_irq_B,
    output  reg         clr_flag_A,
    output  reg         clr_flag_B,
    output  reg         clr_run_A,
    output  reg         clr_run_B,
    output  reg         set_run_A,
    output  reg         set_run_B,
    input               overflow_A,

    `ifdef TEST_SUPPORT     
    // Test
    output  reg     test_eg,
    output  reg     test_op0,
    `endif
    // REG
    output  [1:0]   rl_I,
    output  [2:0]   fb_II,
    output  [2:0]   con_I,
    output  [6:0]   kc_I,
    output  [5:0]   kf_I,
    output  [2:0]   pms_I,
    output  [1:0]   ams_VII,
    output  [2:0]   dt1_II,
    output  [3:0]   mul_VI,
    output  [6:0]   tl_VII,
    output  [1:0]   ks_III,
    output  [4:0]   arate_II,
    output          amsen_VII,
    output  [4:0]   rate1_II,
    output  [1:0]   dt2_I,
    output  [4:0]   rate2_II,
    output  [3:0]   d1l_I,
    output  [3:0]   rrate_II,
    output          keyon_II,

    output  [1:0]   cur_op,
    output          op31_no,
    output          op31_acc,

    output          zero,
    output          m1_enters,
    output          m2_enters,
    output          c1_enters,
    output          c2_enters,
    // Operator
    output          use_prevprev1,
    output          use_internal_x,
    output          use_internal_y, 
    output          use_prev2,
    output          use_prev1
);

reg [7:0] selected_register, din_latch;

`ifdef SIMULATION
reg mmr_dump;
`endif

parameter   REG_TEST    =   8'h01,
            REG_TEST2   =   8'h02,
            REG_KON     =   8'h08,
            REG_NOISE   =   8'h0f,
            REG_CLKA1   =   8'h10,
            REG_CLKA2   =   8'h11,
            REG_CLKB    =   8'h12,
            REG_TIMER   =   8'h14,
            REG_LFRQ    =   8'h18,
            REG_PMDAMD  =   8'h19,
            REG_CTW     =   8'h1b,
            REG_DUMP    =   8'h1f;

reg csm, up_keyon;
reg old_write;
reg [2:0] up_ch;    // channel  to update
reg [1:0] up_op;    // operator to update
reg [5:0] up_opreg; // operator register to update
reg [3:0] up_chreg; // channel  register to update


always @(posedge clk)
    old_write <= write;

always @(posedge clk) begin : memory_mapped_registers
    if( rst ) begin
        selected_register   <= 8'h0;
        `ifdef TEST_SUPPORT
        { test_eg, test_op0 } <= 2'd0;
        `endif
        // timers
        { value_A, value_B } <= 18'd0;
        { clr_flag_B, clr_flag_A,
        enable_irq_B, enable_irq_A, load_B, load_A } <= 6'd0;
        { clr_run_A, clr_run_B, set_run_A, set_run_B } <= 4'b1100;
        // LFO
        { lfo_amd, lfo_pmd }    <= 14'h0;
        lfo_freq        <= 8'd0;
        lfo_w           <= 2'd0;
        lfo_rst         <= 1'b0;
        { ct2, ct1 }    <= 2'd0;
        csm             <= 1'b0;
        din_latch       <= 8'd0;
        `ifdef SIMULATION
        mmr_dump <= 1'b0;
        `endif
    end else begin
        // WRITE IN REGISTERS
        if( write ) begin
            if( !a0 )
                selected_register <= d_in;
            else begin
                // Global registers
                din_latch <= d_in;
                up_keyon <= selected_register == REG_KON;
                up_ch <= selected_register[2:0];
                up_op <= selected_register[4:3];
                case( selected_register)
                    // registros especiales
                    REG_TEST:   lfo_rst <= 1'b1; // regardless of d_in
                    `ifdef TEST_SUPPORT
                    REG_TEST2:  { test_op0, test_eg } <= d_in[1:0];
                    `endif
                    REG_NOISE:  { ne, nfrq } <= { d_in[7], d_in[4:0] };
                    REG_CLKA1:  value_A[9:2]<= d_in;
                    REG_CLKA2:  value_A[1:0]<= d_in[1:0];
                    REG_CLKB:   value_B     <= d_in;
                    REG_TIMER: begin
                        csm <= d_in[7];
                        { clr_flag_B, clr_flag_A,
                          enable_irq_B, enable_irq_A,
                          load_B, load_A } <= d_in[5:0];
                        end
                    REG_LFRQ:   lfo_freq <= d_in;
                    REG_PMDAMD: begin
                        if( !d_in[7] )
                            lfo_amd <= d_in[6:0];
                        else
                            lfo_pmd <= d_in[6:0];                       
                        end
                    REG_CTW: begin
                        { ct2, ct1 } <= d_in[7:6];
                        lfo_w        <= d_in[1:0];
                        end
                    `ifdef SIMULATION
                    REG_DUMP:
                        mmr_dump <= 1'b1;
                    `endif
                    default:;
                endcase
                if( selected_register>8'h30 && selected_register[4:3]==2'b11 ) 
                    { up_chreg, up_opreg } <= 10'd0;
                else
                    casez( selected_register )
                        // channel registers
                        8'b001_00_???: { up_chreg, up_opreg } <= { 4'h1, 6'd0 }; // 0x20 RL, FB, CON
                        8'b001_01_???: { up_chreg, up_opreg } <= { 4'h2, 6'd0 }; // 0x28 KC
                        8'b001_10_???: { up_chreg, up_opreg } <= { 4'h4, 6'd0 }; // 0x30 KF
                        8'b001_11_???: { up_chreg, up_opreg } <= { 4'h8, 6'd0 }; // 0x38 PMS/AMS
                        // operator registers
                        8'b010?_????: { up_chreg, up_opreg } <= 10'h01; // 0x40-0x5F DT1, MUL
                        8'b011?_????: { up_chreg, up_opreg } <= 10'h02; // 0x60-0x7F TL
                        8'b100?_????: { up_chreg, up_opreg } <= 10'h04; // 0x80-0x9F KS, AR
                        8'b101?_????: { up_chreg, up_opreg } <= 10'h08; // 0xA0-0xBF AMS-EN, D1R
                        8'b110?_????: { up_chreg, up_opreg } <= 10'h10; // 0xC0-0xDF DT2, D2R
                        8'b111?_????: { up_chreg, up_opreg } <= 10'h20; // 0xE0-0xFF D1K, RR
                    endcase // selected_register
            end
        end
        else if(clk_en) begin /* clear once-only bits */
            `ifdef SIMULATION
            mmr_dump <= 1'b0;
            `endif
            csm     <= 1'b0;
            lfo_rst <= 1'b0;
            { clr_flag_B, clr_flag_A } <= 2'd0;
        end
    end
end

reg [4:0] busy_cnt; // busy lasts for 32 synth clock cycles, like in real chip

always @(posedge clk)
    if( rst ) begin
        busy <= 1'b0;
        busy_cnt <= 5'd0;
    end
    else begin
        if (!old_write && write && a0 ) begin // only set for data writes
            busy <= 1'b1;
            busy_cnt <= 5'd0;
        end
        else if(clk_en) begin
            if( busy_cnt == 5'd31 ) busy <= 1'b0;
            busy_cnt <= busy_cnt+5'd1;
        end
    end

jt51_reg u_reg(
    .rst        ( rst           ),
    .clk        ( clk           ),
    .clk_en     ( clk_en        ),
    .d_in       ( din_latch     ),
    // channel update
    .up_rl      ( up_chreg[0]   ),
    .up_kc      ( up_chreg[1]   ),
    .up_kf      ( up_chreg[2]   ),
    .up_pms     ( up_chreg[3]   ),
    // operator update
    .up_dt1     ( up_opreg[0]   ),
    .up_tl      ( up_opreg[1]   ),
    .up_ks      ( up_opreg[2]   ),
    .up_amsen   ( up_opreg[3]   ),
    .up_dt2     ( up_opreg[4]   ),
    .up_d1l     ( up_opreg[5]   ),

    .up_keyon   ( up_keyon  ),
    .op         ( up_op     ),      // operator to update
    .ch         ( up_ch     ),      // channel to update
    
    .csm        ( csm       ),
    .overflow_A ( overflow_A),

    .rl_I       ( rl_I      ),
    .fb_II      ( fb_II     ),
    .con_I      ( con_I     ),

    .kc_I       ( kc_I      ),
    .kf_I       ( kf_I      ),
    .pms_I      ( pms_I     ),
    .ams_VII    ( ams_VII   ),

    .dt1_II     ( dt1_II    ),
    .dt2_I      ( dt2_I     ),
    .mul_VI     ( mul_VI    ),
    .tl_VII     ( tl_VII    ),
    .ks_III     ( ks_III    ),

    .arate_II   ( arate_II  ),
    .amsen_VII  ( amsen_VII ),
    .rate1_II   ( rate1_II  ),
    .rate2_II   ( rate2_II  ),
    .rrate_II   ( rrate_II  ),
    .d1l_I      ( d1l_I     ),
    .keyon_II   ( keyon_II  ),

    .cur_op     ( cur_op    ),
    .op31_no    ( op31_no   ),
    .op31_acc   ( op31_acc  ),
    .zero       ( zero      ),
    .m1_enters  ( m1_enters ),
    .m2_enters  ( m2_enters ),
    .c1_enters  ( c1_enters ),
    .c2_enters  ( c2_enters ),
    // Operator
    .use_prevprev1  ( use_prevprev1     ),
    .use_internal_x ( use_internal_x    ),
    .use_internal_y ( use_internal_y    ),
    .use_prev2      ( use_prev2         ),
    .use_prev1      ( use_prev1         )
);

`ifdef SIMULATION
/* verilator lint_off PINMISSING */
wire [4:0] cnt_aux;

sep32_cnt u_sep32_cnt (.clk(clk), .zero(zero), .cnt(cnt_aux));

sep32 #(.width(2),.stg(1)) sep_rl (.clk(clk),.cnt(cnt_aux),.mixed( rl_I     ));
sep32 #(.width(3),.stg(2)) sep_fb (.clk(clk),.cnt(cnt_aux),.mixed( fb_II    ));
sep32 #(.width(3),.stg(1)) sep_con(.clk(clk),.cnt(cnt_aux),.mixed( con_I    ));

sep32 #(.width(7),.stg(1)) sep_kc (.clk(clk),.cnt(cnt_aux),.mixed( kc_I     ));
sep32 #(.width(6),.stg(1)) sep_kf (.clk(clk),.cnt(cnt_aux),.mixed( kf_I     ));
sep32 #(.width(3),.stg(1)) sep_pms(.clk(clk),.cnt(cnt_aux),.mixed( pms_I    ));
sep32 #(.width(2),.stg(7)) sep_ams(.clk(clk),.cnt(cnt_aux),.mixed( ams_VII  ));

sep32 #(.width(3),.stg(2)) sep_dt1(.clk(clk),.cnt(cnt_aux),.mixed( dt1_II   ));
sep32 #(.width(2),.stg(1)) sep_dt2(.clk(clk),.cnt(cnt_aux),.mixed( dt2_I    ));
sep32 #(.width(4),.stg(6)) sep_mul(.clk(clk),.cnt(cnt_aux),.mixed( mul_VI   ));
sep32 #(.width(7),.stg(7)) sep_tl (.clk(clk),.cnt(cnt_aux),.mixed( tl_VII   ));
sep32 #(.width(2),.stg(3)) sep_ks (.clk(clk),.cnt(cnt_aux),.mixed( ks_III   ));

sep32 #(.width(5),.stg(2)) sep_ar (.clk(clk),.cnt(cnt_aux),.mixed( arate_II ));
sep32 #(.width(1),.stg(7)) sep_ame(.clk(clk),.cnt(cnt_aux),.mixed( amsen_VII));
sep32 #(.width(5),.stg(2)) sep_dr1(.clk(clk),.cnt(cnt_aux),.mixed( rate1_II ));
sep32 #(.width(5),.stg(2)) sep_dr2(.clk(clk),.cnt(cnt_aux),.mixed( rate2_II ));
sep32 #(.width(4),.stg(2)) sep_rr (.clk(clk),.cnt(cnt_aux),.mixed( rrate_II ));
sep32 #(.width(4),.stg(1)) sep_d1l(.clk(clk),.cnt(cnt_aux),.mixed( d1l_I    ));
`endif

endmodule
