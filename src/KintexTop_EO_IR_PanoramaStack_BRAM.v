//------------------------------------------------------------------------------
// Combined EO + IR I2C-select top
// - mode 0x07..0x0C => EO camera 0..5 routed to HD-SDI output
// - mode 0x0D..0x12 => IR camera 0..5 routed to HD-SDI output through an
//   internal dual-clock frame buffer and also mirrored to IEG0/IEG1 debug
// - mode 0x14       => all six IR cameras stacked into one 1920x1080 HD-SDI frame
// - legacy mode 0x00..0x05 => IR camera 0..5 (backward compatible)
// - I2C slave exposes full 8-bit register-addressed map at 7-bit address 0x36
//------------------------------------------------------------------------------
module KintexTop_EO_IR_Combined_HD_SDI(
    // EO Camera 0..5
    input  wire         CAM0_PCLK,
    input  wire [7:0]   CAM0_YOUT,
    input  wire [7:0]   CAM0_COUT,

    input  wire         CAM1_PCLK,
    input  wire [7:0]   CAM1_YOUT,
    input  wire [7:0]   CAM1_COUT,
    output wire         TRIG_IN1,

    input  wire         CAM2_PCLK,
    input  wire [7:0]   CAM2_YOUT,
    input  wire [7:0]   CAM2_COUT,
    output wire         TRIG_IN2,

    input  wire         CAM3_PCLK,
    input  wire [7:0]   CAM3_YOUT,
    input  wire [7:0]   CAM3_COUT,
    output wire         TRIG_IN3,

    input  wire         CAM4_PCLK,
    input  wire [7:0]   CAM4_YOUT,
    input  wire [7:0]   CAM4_COUT,
    output wire         TRIG_IN4,

    input  wire         CAM5_PCLK,
    input  wire [7:0]   CAM5_YOUT,
    input  wire [7:0]   CAM5_COUT,
    output wire         TRIG_IN5,

    input  wire         STROBE_OUT0,

    // IR Camera 0..5
    input  wire         IRCAM0_PCLK,
    input  wire         IRCAM0_HSYNC,
    input  wire         IRCAM0_VSYNC,
    input  wire [15:0]  IRCAM0_DOUT,
    output wire         IRCAM0_GENLOCK,

    input  wire         IRCAM1_PCLK,
    input  wire         IRCAM1_HSYNC,
    input  wire         IRCAM1_VSYNC,
    input  wire [15:0]  IRCAM1_DOUT,
    output wire         IRCAM1_GENLOCK,

    input  wire         IRCAM2_PCLK,
    input  wire         IRCAM2_HSYNC,
    input  wire         IRCAM2_VSYNC,
    input  wire [15:0]  IRCAM2_DOUT,
    output wire         IRCAM2_GENLOCK,

    input  wire         IRCAM3_PCLK,
    input  wire         IRCAM3_HSYNC,
    input  wire         IRCAM3_VSYNC,
    input  wire [15:0]  IRCAM3_DOUT,
    output wire         IRCAM3_GENLOCK,

    input  wire         IRCAM4_PCLK,
    input  wire         IRCAM4_HSYNC,
    input  wire         IRCAM4_VSYNC,
    input  wire [15:0]  IRCAM4_DOUT,
    output wire         IRCAM4_GENLOCK,

    input  wire         IRCAM5_PCLK,
    input  wire         IRCAM5_HSYNC,
    input  wire         IRCAM5_VSYNC,
    input  wire [15:0]  IRCAM5_DOUT,
    output wire         IRCAM5_GENLOCK,

    // HD-SDI output for EO selection
    output wire         HD_DE,
    output wire         HD_VSYNC,
    output wire         HD_HSYNC,
    output wire         HD_PCLK,
    output wire [19:0]  HD_DOUT,

    // Debugger outputs for IR selection
    output wire         IEG0_PCLK,
    output wire         IEG0_HSYNC,
    output wire         IEG0_VSYNC,
    output wire [19:0]  IEG0_DOUT,

    output wire         IEG1_PCLK,
    output wire         IEG1_HSYNC,
    output wire         IEG1_VSYNC,
    output wire [19:0]  IEG1_DOUT,

    // I2C
    input  wire         SCL,
    inout  wire         SDA
);

    wire nRESET = 1'b1;

    // ------------------------------------------------------------------------
    // Clock buffers
    // ------------------------------------------------------------------------
    wire IRCAM0_PCLK_bufg, IRCAM1_PCLK_bufg, IRCAM2_PCLK_bufg;
    wire IRCAM3_PCLK_bufg, IRCAM4_PCLK_bufg, IRCAM5_PCLK_bufg;
    wire CAM0_PCLK_ibuf, CAM0_PCLK_bufg;

    IBUFG U_ircam0_pclk_ibuf (.I(IRCAM0_PCLK), .O(IRCAM0_PCLK_bufg));
    IBUFG U_ircam1_pclk_ibuf (.I(IRCAM1_PCLK), .O(IRCAM1_PCLK_bufg));
    IBUFG U_ircam2_pclk_ibuf (.I(IRCAM2_PCLK), .O(IRCAM2_PCLK_bufg));
    IBUFG U_ircam3_pclk_ibuf (.I(IRCAM3_PCLK), .O(IRCAM3_PCLK_bufg));
    IBUFG U_ircam4_pclk_ibuf (.I(IRCAM4_PCLK), .O(IRCAM4_PCLK_bufg));
    IBUFG U_ircam5_pclk_ibuf (.I(IRCAM5_PCLK), .O(IRCAM5_PCLK_bufg));
    IBUF  U_cam0_pclk_ibuf  (.I(CAM0_PCLK),   .O(CAM0_PCLK_ibuf));
    BUFG  U_cam0_pclk_bufg  (.I(CAM0_PCLK_ibuf), .O(CAM0_PCLK_bufg));

    // ------------------------------------------------------------------------
    // IR capture latches
    // ------------------------------------------------------------------------
    reg [15:0] IRCAM0_DOUT_1d, IRCAM1_DOUT_1d, IRCAM2_DOUT_1d;
    reg [15:0] IRCAM3_DOUT_1d, IRCAM4_DOUT_1d, IRCAM5_DOUT_1d;
    reg        IRCAM0_HSYNC_1d, IRCAM0_VSYNC_1d;
    reg        IRCAM1_HSYNC_1d, IRCAM1_VSYNC_1d;
    reg        IRCAM2_HSYNC_1d, IRCAM2_VSYNC_1d;
    reg        IRCAM3_HSYNC_1d, IRCAM3_VSYNC_1d;
    reg        IRCAM4_HSYNC_1d, IRCAM4_VSYNC_1d;
    reg        IRCAM5_HSYNC_1d, IRCAM5_VSYNC_1d;

    always @(posedge IRCAM0_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM0_DOUT_1d <= 16'h0000; IRCAM0_HSYNC_1d <= 1'b0; IRCAM0_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM0_DOUT_1d <= IRCAM0_DOUT; IRCAM0_HSYNC_1d <= IRCAM0_HSYNC; IRCAM0_VSYNC_1d <= IRCAM0_VSYNC;
        end
    end
    always @(posedge IRCAM1_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM1_DOUT_1d <= 16'h0000; IRCAM1_HSYNC_1d <= 1'b0; IRCAM1_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM1_DOUT_1d <= IRCAM1_DOUT; IRCAM1_HSYNC_1d <= IRCAM1_HSYNC; IRCAM1_VSYNC_1d <= IRCAM1_VSYNC;
        end
    end
    always @(posedge IRCAM2_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM2_DOUT_1d <= 16'h0000; IRCAM2_HSYNC_1d <= 1'b0; IRCAM2_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM2_DOUT_1d <= IRCAM2_DOUT; IRCAM2_HSYNC_1d <= IRCAM2_HSYNC; IRCAM2_VSYNC_1d <= IRCAM2_VSYNC;
        end
    end
    always @(posedge IRCAM3_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM3_DOUT_1d <= 16'h0000; IRCAM3_HSYNC_1d <= 1'b0; IRCAM3_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM3_DOUT_1d <= IRCAM3_DOUT; IRCAM3_HSYNC_1d <= IRCAM3_HSYNC; IRCAM3_VSYNC_1d <= IRCAM3_VSYNC;
        end
    end
    always @(posedge IRCAM4_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM4_DOUT_1d <= 16'h0000; IRCAM4_HSYNC_1d <= 1'b0; IRCAM4_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM4_DOUT_1d <= IRCAM4_DOUT; IRCAM4_HSYNC_1d <= IRCAM4_HSYNC; IRCAM4_VSYNC_1d <= IRCAM4_VSYNC;
        end
    end
    always @(posedge IRCAM5_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            IRCAM5_DOUT_1d <= 16'h0000; IRCAM5_HSYNC_1d <= 1'b0; IRCAM5_VSYNC_1d <= 1'b0;
        end else begin
            IRCAM5_DOUT_1d <= IRCAM5_DOUT; IRCAM5_HSYNC_1d <= IRCAM5_HSYNC; IRCAM5_VSYNC_1d <= IRCAM5_VSYNC;
        end
    end

    // ------------------------------------------------------------------------
    // I2C slave / mode decode
    // ------------------------------------------------------------------------
    wire [3:0] cam_select_unused;
    wire [7:0] mode_current;
    wire [127:0] i2c_debug_status;

    Kintex_top_I2C_test #(
        .SLAVE_ADDR(7'h36),
        .SCLK_HZ(74_250_000),
        .POR_MS(100)
    ) u_i2c (
        .FPGA_RESET(1'b1),
        .SCLK_IN   (CAM0_PCLK_ibuf),
        .SCL       (SCL),
        .SDA       (SDA),
        .debug_status(i2c_debug_status),
        .cam_select(cam_select_unused),
        .mode_out  (mode_current)
    );

    wire eo_single_mode_active = (mode_current >= 8'h07) && (mode_current <= 8'h0C);
    wire eo_stack_mode_active  = (mode_current == 8'h15);
    wire ir_single_mode_active = (mode_current <= 8'd5) || ((mode_current >= 8'h0D) && (mode_current <= 8'h12));
    wire ir_stack_mode_active  = (mode_current == 8'h14);
    wire ir_mode_active        = ir_single_mode_active || ir_stack_mode_active;

    wire [2:0] eo_sel = eo_single_mode_active ? (mode_current - 8'h07) : 3'd0;
    wire [2:0] ir_sel = (mode_current <= 8'd5) ? mode_current[2:0] :
                        (((mode_current >= 8'h0D) && (mode_current <= 8'h12)) ? (mode_current - 8'h0D) : 3'd0);

    // ------------------------------------------------------------------------
    // EO camera processing blocks (reused from previous working EO design)
    // ------------------------------------------------------------------------
    wire        eo0_pclk, eo0_hsync, eo0_vsync;
    wire [19:2] eo0_dout_19_2;
    wire [19:0] eo0_dout = {eo0_dout_19_2, 2'b00};
    wire        eo0_dbg_pclk, eo0_dbg_hsync, eo0_dbg_vsync;
    wire [19:0] eo0_dbg_dout;

    wire        eo1_pclk, eo1_hsync, eo1_vsync;
    wire [19:0] eo1_dout, eo1_dbg_dout;
    wire        eo1_dbg_pclk, eo1_dbg_hsync, eo1_dbg_vsync;

    wire        eo2_pclk, eo2_hsync, eo2_vsync;
    wire [19:0] eo2_dout, eo2_dbg_dout;
    wire        eo2_dbg_pclk, eo2_dbg_hsync, eo2_dbg_vsync;

    wire        eo3_pclk, eo3_hsync, eo3_vsync;
    wire [19:0] eo3_dout, eo3_dbg_dout;
    wire        eo3_dbg_pclk, eo3_dbg_hsync, eo3_dbg_vsync;

    wire        eo4_pclk, eo4_hsync, eo4_vsync;
    wire [19:0] eo4_dout, eo4_dbg_dout;
    wire        eo4_dbg_pclk, eo4_dbg_hsync, eo4_dbg_vsync;

    wire        eo5_pclk, eo5_hsync, eo5_vsync;
    wire [19:0] eo5_dout, eo5_dbg_dout;
    wire        eo5_dbg_pclk, eo5_dbg_hsync, eo5_dbg_vsync;

    Kintex_top_0cam_1ch u_eo0 (
        .FPGA_RESET (nRESET),
        .CAM0_PCLK  (CAM0_PCLK_ibuf),
        .CAM0_YOUT  (CAM0_YOUT),
        .CAM0_COUT  (CAM0_COUT),
        .IEG0_PCLK  (eo0_pclk),
        .IEG0_HSYNC (eo0_hsync),
        .IEG0_VSYNC (eo0_vsync),
        .IEG0_DOUT  (eo0_dout_19_2),
        .IEG1_PCLK  (eo0_dbg_pclk),
        .IEG1_HSYNC (eo0_dbg_hsync),
        .IEG1_VSYNC (eo0_dbg_vsync),
        .IEG1_DOUT  (eo0_dbg_dout)
    );

    Kintex_top_1cam_1ch u_eo1 (
        .FPGA_RESET (nRESET),
        .CAM1_PCLK  (CAM1_PCLK),
        .CAM1_YOUT  (CAM1_YOUT),
        .CAM1_COUT  (CAM1_COUT),
        .STROBE_OUT0(STROBE_OUT0),
        .TRIG_IN1   (TRIG_IN1),
        .IEG0_PCLK  (eo1_pclk),
        .IEG0_HSYNC (eo1_hsync),
        .IEG0_VSYNC (eo1_vsync),
        .IEG0_DOUT  (eo1_dout),
        .IEG1_PCLK  (eo1_dbg_pclk),
        .IEG1_HSYNC (eo1_dbg_hsync),
        .IEG1_VSYNC (eo1_dbg_vsync),
        .IEG1_DOUT  (eo1_dbg_dout)
    );

    Kintex_top_2cam_1ch u_eo2 (
        .FPGA_RESET (nRESET),
        .CAM2_PCLK  (CAM2_PCLK),
        .CAM2_YOUT  (CAM2_YOUT),
        .CAM2_COUT  (CAM2_COUT),
        .STROBE_OUT0(STROBE_OUT0),
        .TRIG_IN2   (TRIG_IN2),
        .IEG0_PCLK  (eo2_pclk),
        .IEG0_HSYNC (eo2_hsync),
        .IEG0_VSYNC (eo2_vsync),
        .IEG0_DOUT  (eo2_dout),
        .IEG1_PCLK  (eo2_dbg_pclk),
        .IEG1_HSYNC (eo2_dbg_hsync),
        .IEG1_VSYNC (eo2_dbg_vsync),
        .IEG1_DOUT  (eo2_dbg_dout)
    );

    Kintex_top_3cam_1ch u_eo3 (
        .FPGA_RESET (nRESET),
        .CAM3_PCLK  (CAM3_PCLK),
        .CAM3_YOUT  (CAM3_YOUT),
        .CAM3_COUT  (CAM3_COUT),
        .STROBE_OUT0(STROBE_OUT0),
        .TRIG_IN3   (TRIG_IN3),
        .IEG0_PCLK  (eo3_pclk),
        .IEG0_HSYNC (eo3_hsync),
        .IEG0_VSYNC (eo3_vsync),
        .IEG0_DOUT  (eo3_dout),
        .IEG1_PCLK  (eo3_dbg_pclk),
        .IEG1_HSYNC (eo3_dbg_hsync),
        .IEG1_VSYNC (eo3_dbg_vsync),
        .IEG1_DOUT  (eo3_dbg_dout)
    );

    Kintex_top_4cam_1ch u_eo4 (
        .FPGA_RESET (nRESET),
        .CAM4_PCLK  (CAM4_PCLK),
        .CAM4_YOUT  (CAM4_YOUT),
        .CAM4_COUT  (CAM4_COUT),
        .STROBE_OUT0(STROBE_OUT0),
        .TRIG_IN4   (TRIG_IN4),
        .IEG0_PCLK  (eo4_pclk),
        .IEG0_HSYNC (eo4_hsync),
        .IEG0_VSYNC (eo4_vsync),
        .IEG0_DOUT  (eo4_dout),
        .IEG1_PCLK  (eo4_dbg_pclk),
        .IEG1_HSYNC (eo4_dbg_hsync),
        .IEG1_VSYNC (eo4_dbg_vsync),
        .IEG1_DOUT  (eo4_dbg_dout)
    );

    Kintex_top_5cam_1ch u_eo5 (
        .FPGA_RESET (nRESET),
        .CAM5_PCLK  (CAM5_PCLK),
        .CAM5_YOUT  (CAM5_YOUT),
        .CAM5_COUT  (CAM5_COUT),
        .STROBE_OUT0(STROBE_OUT0),
        .TRIG_IN5   (TRIG_IN5),
        .IEG0_PCLK  (eo5_pclk),
        .IEG0_HSYNC (eo5_hsync),
        .IEG0_VSYNC (eo5_vsync),
        .IEG0_DOUT  (eo5_dout),
        .IEG1_PCLK  (eo5_dbg_pclk),
        .IEG1_HSYNC (eo5_dbg_hsync),
        .IEG1_VSYNC (eo5_dbg_vsync),
        .IEG1_DOUT  (eo5_dbg_dout)
    );

    wire eo_sel_pclk_mux = (eo_sel == 3'd0) ? eo0_pclk :
                           (eo_sel == 3'd1) ? eo1_pclk :
                           (eo_sel == 3'd2) ? eo2_pclk :
                           (eo_sel == 3'd3) ? eo3_pclk :
                           (eo_sel == 3'd4) ? eo4_pclk :
                                              eo5_pclk;
    wire EO_SEL_PCLK_BUFG;
    BUFG u_eo_sel_pclk_bufg (.I(eo_sel_pclk_mux), .O(EO_SEL_PCLK_BUFG));

    wire        EO_SEL_HSYNC = (eo_sel == 3'd0) ? eo0_hsync :
                               (eo_sel == 3'd1) ? eo1_hsync :
                               (eo_sel == 3'd2) ? eo2_hsync :
                               (eo_sel == 3'd3) ? eo3_hsync :
                               (eo_sel == 3'd4) ? eo4_hsync : eo5_hsync;
    wire        EO_SEL_VSYNC = (eo_sel == 3'd0) ? eo0_vsync :
                               (eo_sel == 3'd1) ? eo1_vsync :
                               (eo_sel == 3'd2) ? eo2_vsync :
                               (eo_sel == 3'd3) ? eo3_vsync :
                               (eo_sel == 3'd4) ? eo4_vsync : eo5_vsync;
    wire [19:0] EO_SEL_DOUT  = (eo_sel == 3'd0) ? eo0_dout :
                               (eo_sel == 3'd1) ? eo1_dout :
                               (eo_sel == 3'd2) ? eo2_dout :
                               (eo_sel == 3'd3) ? eo3_dout :
                               (eo_sel == 3'd4) ? eo4_dout : eo5_dout;

    wire        eo_stack_hd_de;
    wire        eo_stack_hd_hsync;
    wire        eo_stack_hd_vsync;
    wire [19:0] eo_stack_hd_dout;

    // EO single-camera mode is a zero-latency direct passthrough of the selected
    // camera on its own pixel clock (driven in the HD_* output mux below).
    // Buffering a single 1920x1080 stream adds latency and, because the selected
    // camera's PCLK is not the HD read clock, introduces chroma-phase (Cb/Cr =
    // red/blue) and raster-offset drift. Passthrough avoids all of that.

    EO6Stack_To_HD1080p_Buffered u_eo_stack_to_hd (
        .rst_n        (nRESET),
        .rd_clk       (CAM0_PCLK_bufg),
        .cam0_wr_clk  (eo0_pclk),
        .cam0_wr_hsync(eo0_hsync),
        .cam0_wr_vsync(eo0_vsync),
        .cam0_wr_pixel(eo0_dout),
        .cam1_wr_clk  (eo1_pclk),
        .cam1_wr_hsync(eo1_hsync),
        .cam1_wr_vsync(eo1_vsync),
        .cam1_wr_pixel(eo1_dout),
        .cam2_wr_clk  (eo2_pclk),
        .cam2_wr_hsync(eo2_hsync),
        .cam2_wr_vsync(eo2_vsync),
        .cam2_wr_pixel(eo2_dout),
        .cam3_wr_clk  (eo3_pclk),
        .cam3_wr_hsync(eo3_hsync),
        .cam3_wr_vsync(eo3_vsync),
        .cam3_wr_pixel(eo3_dout),
        .cam4_wr_clk  (eo4_pclk),
        .cam4_wr_hsync(eo4_hsync),
        .cam4_wr_vsync(eo4_vsync),
        .cam4_wr_pixel(eo4_dout),
        .cam5_wr_clk  (eo5_pclk),
        .cam5_wr_hsync(eo5_hsync),
        .cam5_wr_vsync(eo5_vsync),
        .cam5_wr_pixel(eo5_dout),
        .hd_de        (eo_stack_hd_de),
        .hd_hsync     (eo_stack_hd_hsync),
        .hd_vsync     (eo_stack_hd_vsync),
        .hd_dout      (eo_stack_hd_dout)
    );

    // ------------------------------------------------------------------------
    // EO timing diagnostics (I2C read-only registers 0x70..0x7F)
    // ------------------------------------------------------------------------
    wire [23:0] eo0_frame_period_src, eo1_frame_period_src, eo2_frame_period_src;
    wire [23:0] eo3_frame_period_src, eo4_frame_period_src, eo5_frame_period_src;
    wire        eo0_frame_toggle_src, eo1_frame_toggle_src, eo2_frame_toggle_src;
    wire        eo3_frame_toggle_src, eo4_frame_toggle_src, eo5_frame_toggle_src;
    wire [23:0] eo0_frame_period_cam0, eo1_frame_period_cam0, eo2_frame_period_cam0;
    wire [23:0] eo3_frame_period_cam0, eo4_frame_period_cam0, eo5_frame_period_cam0;
    wire [23:0] eo_selected_frame_period_cam0;
    wire [23:0] eo_stack_hd_period_cam0;
    wire [31:0] eo_strobe_period_cam0;
    wire        strobe_out0_sync_cam0;

    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo0_period (
        .rst_n(nRESET), .clk(eo0_pclk), .frame_signal(eo0_vsync),
        .period_cycles(eo0_frame_period_src), .frame_toggle(eo0_frame_toggle_src)
    );
    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo1_period (
        .rst_n(nRESET), .clk(eo1_pclk), .frame_signal(eo1_vsync),
        .period_cycles(eo1_frame_period_src), .frame_toggle(eo1_frame_toggle_src)
    );
    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo2_period (
        .rst_n(nRESET), .clk(eo2_pclk), .frame_signal(eo2_vsync),
        .period_cycles(eo2_frame_period_src), .frame_toggle(eo2_frame_toggle_src)
    );
    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo3_period (
        .rst_n(nRESET), .clk(eo3_pclk), .frame_signal(eo3_vsync),
        .period_cycles(eo3_frame_period_src), .frame_toggle(eo3_frame_toggle_src)
    );
    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo4_period (
        .rst_n(nRESET), .clk(eo4_pclk), .frame_signal(eo4_vsync),
        .period_cycles(eo4_frame_period_src), .frame_toggle(eo4_frame_toggle_src)
    );
    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(0)) u_eo5_period (
        .rst_n(nRESET), .clk(eo5_pclk), .frame_signal(eo5_vsync),
        .period_cycles(eo5_frame_period_src), .frame_toggle(eo5_frame_toggle_src)
    );

    PeriodCdcCapture #(.WIDTH(24)) u_eo0_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo0_frame_period_src),
        .src_toggle(eo0_frame_toggle_src), .dst_period(eo0_frame_period_cam0)
    );
    PeriodCdcCapture #(.WIDTH(24)) u_eo1_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo1_frame_period_src),
        .src_toggle(eo1_frame_toggle_src), .dst_period(eo1_frame_period_cam0)
    );
    PeriodCdcCapture #(.WIDTH(24)) u_eo2_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo2_frame_period_src),
        .src_toggle(eo2_frame_toggle_src), .dst_period(eo2_frame_period_cam0)
    );
    PeriodCdcCapture #(.WIDTH(24)) u_eo3_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo3_frame_period_src),
        .src_toggle(eo3_frame_toggle_src), .dst_period(eo3_frame_period_cam0)
    );
    PeriodCdcCapture #(.WIDTH(24)) u_eo4_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo4_frame_period_src),
        .src_toggle(eo4_frame_toggle_src), .dst_period(eo4_frame_period_cam0)
    );
    PeriodCdcCapture #(.WIDTH(24)) u_eo5_period_cdc (
        .rst_n(nRESET), .dst_clk(CAM0_PCLK_bufg), .src_period(eo5_frame_period_src),
        .src_toggle(eo5_frame_toggle_src), .dst_period(eo5_frame_period_cam0)
    );

    FramePeriodCounter #(.WIDTH(24), .START_ON_RISING(1)) u_eo_stack_hd_period (
        .rst_n(nRESET), .clk(CAM0_PCLK_bufg), .frame_signal(eo_stack_hd_vsync),
        .period_cycles(eo_stack_hd_period_cam0), .frame_toggle()
    );

    EdgePeriodCounter #(.WIDTH(32)) u_strobe_period (
        .rst_n(nRESET), .clk(CAM0_PCLK_bufg), .async_signal(STROBE_OUT0),
        .period_cycles(eo_strobe_period_cam0), .sync_signal(strobe_out0_sync_cam0)
    );

    assign eo_selected_frame_period_cam0 =
        (eo_sel == 3'd0) ? eo0_frame_period_cam0 :
        (eo_sel == 3'd1) ? eo1_frame_period_cam0 :
        (eo_sel == 3'd2) ? eo2_frame_period_cam0 :
        (eo_sel == 3'd3) ? eo3_frame_period_cam0 :
        (eo_sel == 3'd4) ? eo4_frame_period_cam0 :
                           eo5_frame_period_cam0;

    wire [7:0] i2c_dbg_70 = 8'hE0;
    wire [7:0] i2c_dbg_71 = mode_current;
    wire [7:0] i2c_dbg_72 = eo_selected_frame_period_cam0[7:0];
    wire [7:0] i2c_dbg_73 = eo_selected_frame_period_cam0[15:8];
    wire [7:0] i2c_dbg_74 = eo_selected_frame_period_cam0[23:16];
    wire [7:0] i2c_dbg_75 = eo0_frame_period_cam0[7:0];
    wire [7:0] i2c_dbg_76 = eo0_frame_period_cam0[15:8];
    wire [7:0] i2c_dbg_77 = eo0_frame_period_cam0[23:16];
    wire [7:0] i2c_dbg_78 = eo_stack_hd_period_cam0[7:0];
    wire [7:0] i2c_dbg_79 = eo_stack_hd_period_cam0[15:8];
    wire [7:0] i2c_dbg_7a = eo_stack_hd_period_cam0[23:16];
    wire [7:0] i2c_dbg_7b = eo_strobe_period_cam0[7:0];
    wire [7:0] i2c_dbg_7c = eo_strobe_period_cam0[15:8];
    wire [7:0] i2c_dbg_7d = eo_strobe_period_cam0[23:16];
    wire [7:0] i2c_dbg_7e = eo_strobe_period_cam0[31:24];
    wire [7:0] i2c_dbg_7f = {strobe_out0_sync_cam0, eo_stack_mode_active,
                              eo_single_mode_active, 2'b00, eo_sel};

    assign i2c_debug_status = {
        i2c_dbg_7f, i2c_dbg_7e, i2c_dbg_7d, i2c_dbg_7c,
        i2c_dbg_7b, i2c_dbg_7a, i2c_dbg_79, i2c_dbg_78,
        i2c_dbg_77, i2c_dbg_76, i2c_dbg_75, i2c_dbg_74,
        i2c_dbg_73, i2c_dbg_72, i2c_dbg_71, i2c_dbg_70
    };

    // ------------------------------------------------------------------------
    // IR routing
    // ------------------------------------------------------------------------
    wire        IR_SEL_PCLK_MUX_OUT = (ir_sel == 3'd0) ? IRCAM0_PCLK_bufg :
                                      (ir_sel == 3'd1) ? IRCAM1_PCLK_bufg :
                                      (ir_sel == 3'd2) ? IRCAM2_PCLK_bufg :
                                      (ir_sel == 3'd3) ? IRCAM3_PCLK_bufg :
                                      (ir_sel == 3'd4) ? IRCAM4_PCLK_bufg :
                                                         IRCAM5_PCLK_bufg;
    wire IR_SEL_PCLK_BUFG;
    BUFG u_ir_sel_pclk_bufg (.I(IR_SEL_PCLK_MUX_OUT), .O(IR_SEL_PCLK_BUFG));

    wire        IR_SEL_HSYNC = (ir_sel == 3'd0) ? IRCAM0_HSYNC_1d :
                               (ir_sel == 3'd1) ? IRCAM1_HSYNC_1d :
                               (ir_sel == 3'd2) ? IRCAM2_HSYNC_1d :
                               (ir_sel == 3'd3) ? IRCAM3_HSYNC_1d :
                               (ir_sel == 3'd4) ? IRCAM4_HSYNC_1d : IRCAM5_HSYNC_1d;
    wire        IR_SEL_VSYNC = (ir_sel == 3'd0) ? IRCAM0_VSYNC_1d :
                               (ir_sel == 3'd1) ? IRCAM1_VSYNC_1d :
                               (ir_sel == 3'd2) ? IRCAM2_VSYNC_1d :
                               (ir_sel == 3'd3) ? IRCAM3_VSYNC_1d :
                               (ir_sel == 3'd4) ? IRCAM4_VSYNC_1d : IRCAM5_VSYNC_1d;
    wire [7:0]  IR_SEL_GRAY  = (ir_sel == 3'd0) ? IRCAM0_DOUT_1d[13:6] :
                               (ir_sel == 3'd1) ? IRCAM1_DOUT_1d[13:6] :
                               (ir_sel == 3'd2) ? IRCAM2_DOUT_1d[13:6] :
                               (ir_sel == 3'd3) ? IRCAM3_DOUT_1d[13:6] :
                               (ir_sel == 3'd4) ? IRCAM4_DOUT_1d[13:6] :
                                                  IRCAM5_DOUT_1d[13:6];
    wire [19:0] IR_SEL_DOUT  = {12'b0, IR_SEL_GRAY};

    // Keep the raw IR stream visible on the debugger connectors.
    assign IEG0_PCLK  = ir_single_mode_active ? IR_SEL_PCLK_BUFG : 1'b0;
    assign IEG0_HSYNC = ir_single_mode_active ? IR_SEL_HSYNC    : 1'b0;
    assign IEG0_VSYNC = ir_single_mode_active ? IR_SEL_VSYNC    : 1'b0;
    assign IEG0_DOUT  = ir_single_mode_active ? IR_SEL_DOUT     : 20'h0;

    assign IEG1_PCLK  = ir_single_mode_active ? IR_SEL_PCLK_BUFG : 1'b0;
    assign IEG1_HSYNC = ir_single_mode_active ? IR_SEL_HSYNC     : 1'b0;
    assign IEG1_VSYNC = ir_single_mode_active ? IR_SEL_VSYNC     : 1'b0;
    assign IEG1_DOUT  = ir_single_mode_active ? IR_SEL_DOUT      : 20'h0;

    // For IR modes, capture all IR frames into shared per-camera double
    // buffers and render either:
    // - a single selected camera centered in the 1920x1080 raster, or
    // - the 2x3 IR stack layout.
    // Spatial (x,y) addressing makes the output immune to per-camera clock
    // drift; the FPGA-generated genlock strobe (IRCAMx_GENLOCK) frame-aligns
    // the sensors so the shared buffers stay tear-free.
    wire        ir_hd_de;
    wire        ir_hd_hsync;
    wire        ir_hd_vsync;
    wire [19:0] ir_hd_dout;

    IR6Modes_To_HD1080p_Buffered u_ir_modes_to_hd (
        .rst_n        (nRESET),
        .rd_clk       (CAM0_PCLK_bufg),
        .stack_mode   (ir_stack_mode_active),
        .single_sel   (ir_sel),
        .cam0_wr_clk  (IRCAM0_PCLK_bufg),
        .cam0_wr_hsync(IRCAM0_HSYNC_1d),
        .cam0_wr_vsync(IRCAM0_VSYNC_1d),
        .cam0_wr_pixel(IRCAM0_DOUT_1d[13:6]),
        .cam1_wr_clk  (IRCAM1_PCLK_bufg),
        .cam1_wr_hsync(IRCAM1_HSYNC_1d),
        .cam1_wr_vsync(IRCAM1_VSYNC_1d),
        .cam1_wr_pixel(IRCAM1_DOUT_1d[13:6]),
        .cam2_wr_clk  (IRCAM2_PCLK_bufg),
        .cam2_wr_hsync(IRCAM2_HSYNC_1d),
        .cam2_wr_vsync(IRCAM2_VSYNC_1d),
        .cam2_wr_pixel(IRCAM2_DOUT_1d[13:6]),
        .cam3_wr_clk  (IRCAM3_PCLK_bufg),
        .cam3_wr_hsync(IRCAM3_HSYNC_1d),
        .cam3_wr_vsync(IRCAM3_VSYNC_1d),
        .cam3_wr_pixel(IRCAM3_DOUT_1d[13:6]),
        .cam4_wr_clk  (IRCAM4_PCLK_bufg),
        .cam4_wr_hsync(IRCAM4_HSYNC_1d),
        .cam4_wr_vsync(IRCAM4_VSYNC_1d),
        .cam4_wr_pixel(IRCAM4_DOUT_1d[13:6]),
        .cam5_wr_clk  (IRCAM5_PCLK_bufg),
        .cam5_wr_hsync(IRCAM5_HSYNC_1d),
        .cam5_wr_vsync(IRCAM5_VSYNC_1d),
        .cam5_wr_pixel(IRCAM5_DOUT_1d[13:6]),
        .hd_de        (ir_hd_de),
        .hd_hsync     (ir_hd_hsync),
        .hd_vsync     (ir_hd_vsync),
        .hd_dout      (ir_hd_dout)
    );

    assign HD_PCLK  = eo_single_mode_active ? EO_SEL_PCLK_BUFG   :
                      eo_stack_mode_active  ? CAM0_PCLK_bufg     :
                      ir_mode_active        ? CAM0_PCLK_bufg     : 1'b0;
    assign HD_DE    = eo_single_mode_active ? EO_SEL_HSYNC       :
                      eo_stack_mode_active  ? eo_stack_hd_de     :
                      ir_mode_active        ? ir_hd_de           : 1'b0;
    assign HD_HSYNC = eo_single_mode_active ? EO_SEL_HSYNC       :
                      eo_stack_mode_active  ? eo_stack_hd_hsync  :
                      ir_mode_active        ? ir_hd_hsync        : 1'b0;
    assign HD_VSYNC = eo_single_mode_active ? EO_SEL_VSYNC       :
                      eo_stack_mode_active  ? eo_stack_hd_vsync  :
                      ir_mode_active        ? ir_hd_vsync        : 1'b0;
    assign HD_DOUT  = eo_single_mode_active ? EO_SEL_DOUT        :
                      eo_stack_mode_active  ? eo_stack_hd_dout   :
                      ir_mode_active        ? ir_hd_dout         : 20'h0;

    // ------------------------------------------------------------------------
    // IR genlock generation
    // ------------------------------------------------------------------------
    reg sig_60hz;
    localparam integer CLK_HZ        = 74_250_000;
    localparam integer FRAME_HZ_X10  = 600;
    localparam integer PERIOD_CYCLES = (CLK_HZ * 10) / FRAME_HZ_X10;
    localparam integer HIGH_CYCLES   = (PERIOD_CYCLES * 1) / 100;
    localparam integer CW = 22;
    reg [CW-1:0] cnt;

    always @(posedge CAM0_PCLK_bufg or negedge nRESET) begin
        if (!nRESET) begin
            cnt      <= {CW{1'b0}};
            sig_60hz <= 1'b0;
        end else begin
            if (cnt == PERIOD_CYCLES-1)
                cnt <= {CW{1'b0}};
            else
                cnt <= cnt + {{(CW-1){1'b0}}, 1'b1};

            sig_60hz <= (cnt < HIGH_CYCLES);
        end
    end

    assign IRCAM0_GENLOCK = sig_60hz;
    assign IRCAM1_GENLOCK = sig_60hz;
    assign IRCAM2_GENLOCK = sig_60hz;
    assign IRCAM3_GENLOCK = sig_60hz;
    assign IRCAM4_GENLOCK = sig_60hz;
    assign IRCAM5_GENLOCK = sig_60hz;

endmodule

module FramePeriodCounter #(
    parameter integer WIDTH = 24,
    parameter integer START_ON_RISING = 0
)(
    input  wire             rst_n,
    input  wire             clk,
    input  wire             frame_signal,
    output reg  [WIDTH-1:0] period_cycles,
    output reg              frame_toggle
);
    reg [WIDTH-1:0] cycle_count;
    reg             frame_signal_d;
    wire            start_edge = START_ON_RISING ?
                                 (frame_signal && !frame_signal_d) :
                                 (frame_signal_d && !frame_signal);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count    <= {WIDTH{1'b0}};
            period_cycles  <= {WIDTH{1'b0}};
            frame_signal_d <= 1'b0;
            frame_toggle   <= 1'b0;
        end else begin
            frame_signal_d <= frame_signal;

            if (start_edge) begin
                period_cycles <= cycle_count;
                cycle_count   <= {{(WIDTH-1){1'b0}}, 1'b1};
                frame_toggle  <= ~frame_toggle;
            end else if (cycle_count != {WIDTH{1'b1}}) begin
                cycle_count <= cycle_count + {{(WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule

module PeriodCdcCapture #(
    parameter integer WIDTH = 24
)(
    input  wire             rst_n,
    input  wire             dst_clk,
    input  wire [WIDTH-1:0] src_period,
    input  wire             src_toggle,
    output reg  [WIDTH-1:0] dst_period
);
    reg src_toggle_meta;
    reg src_toggle_sync;
    reg src_toggle_sync_d;

    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            src_toggle_meta   <= 1'b0;
            src_toggle_sync   <= 1'b0;
            src_toggle_sync_d <= 1'b0;
            dst_period        <= {WIDTH{1'b0}};
        end else begin
            src_toggle_meta   <= src_toggle;
            src_toggle_sync   <= src_toggle_meta;
            src_toggle_sync_d <= src_toggle_sync;

            if (src_toggle_sync != src_toggle_sync_d)
                dst_period <= src_period;
        end
    end
endmodule

module EdgePeriodCounter #(
    parameter integer WIDTH = 32
)(
    input  wire             rst_n,
    input  wire             clk,
    input  wire             async_signal,
    output reg  [WIDTH-1:0] period_cycles,
    output wire             sync_signal
);
    reg [WIDTH-1:0] cycle_count;
    reg             sig_meta;
    reg             sig_sync;
    reg             sig_sync_d;
    wire            rising_edge = sig_sync && !sig_sync_d;

    assign sync_signal = sig_sync;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count   <= {WIDTH{1'b0}};
            period_cycles <= {WIDTH{1'b0}};
            sig_meta      <= 1'b0;
            sig_sync      <= 1'b0;
            sig_sync_d    <= 1'b0;
        end else begin
            sig_meta   <= async_signal;
            sig_sync   <= sig_meta;
            sig_sync_d <= sig_sync;

            if (rising_edge) begin
                period_cycles <= cycle_count;
                cycle_count   <= {{(WIDTH-1){1'b0}}, 1'b1};
            end else if (cycle_count != {WIDTH{1'b1}}) begin
                cycle_count <= cycle_count + {{(WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule

module IR540x480_GrayFrameBuffer #(
    parameter integer SRC_W        = 540,
    parameter integer SRC_H        = 480,
    parameter integer FRAME_ADDR_W = 18,
    parameter integer READ_LATENCY = 2
)(
    input  wire                    rst_n,
    input  wire                    wr_clk,
    input  wire                    wr_hsync,
    input  wire                    wr_vsync,
    input  wire [7:0]              wr_pixel,
    input  wire                    rd_clk,
    input  wire                    rd_frame_start,
    input  wire                    rd_en,
    input  wire [FRAME_ADDR_W-1:0] rd_addr,
    output wire [7:0]              rd_pixel,
    output reg                     frame_valid
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer WORD_ADDR_W  = FRAME_ADDR_W - 3;
    localparam integer FRAME_WORDS  = FRAME_PIXELS / 8;
    localparam integer FRAME_BITS   = FRAME_WORDS * 64;
    localparam integer FIFO_WIDTH   = 1 + 1 + FRAME_ADDR_W + 8;
    localparam integer IR_IN_H      = 512;
    localparam integer CROP_X_START = 32;
    localparam integer CROP_X_WIDTH = (SRC_W * 16) / 15;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_bank;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    reg [9:0]              wr_x;
    reg [9:0]              wr_y;
    reg [3:0]              wr_x_phase;
    reg [3:0]              wr_y_phase;
    reg                    wr_have_prev_line;
    reg [7:0]              wr_pixel_left;
    reg [7:0]              wr_pixel_above_left;
    (* ram_style = "distributed" *) reg [7:0] wr_prev_line_pixel [0:1023];
    reg rd_bank;
    reg pending_bank;
    reg pending_valid;
    reg [READ_LATENCY-1:0] rd_bank_pipe;
    reg [(3*READ_LATENCY)-1:0] rd_byte_pipe;
    reg [63:0] pack_word;
    reg [63:0] pack_word_next;

    wire [63:0] rd_word_buf0;
    wire [63:0] rd_word_buf1;
    wire [63:0] rd_word_selected;
    wire [2:0] rd_byte_selected;
    wire       wr_fifo_full;
    wire       wr_sample_now;
    wire       wr_frame_start;
    wire       wr_frame_end;
    wire       wr_line_end;
    wire       wr_x_in_crop;
    wire       wr_x_sample;
    wire       wr_y_sample;
    wire [FIFO_WIDTH-1:0] wr_fifo_din;
    wire [7:0] wr_pixel_above_raw;
    wire       wr_left_valid;
    wire [7:0] wr_pixel_left_eff;
    wire [7:0] wr_pixel_above_eff;
    wire [7:0] wr_pixel_above_left_eff;
    wire [7:0] wr_pixel_filtered;
    wire [FIFO_WIDTH-1:0] rd_fifo_dout;
    wire       rd_fifo_empty;
    wire       rd_fifo_pop;
    wire       rd_fifo_last;
    wire       rd_fifo_bank;
    wire [FRAME_ADDR_W-1:0] rd_fifo_addr;
    wire [7:0] rd_fifo_pixel;
    wire [WORD_ADDR_W-1:0] rd_fifo_word_addr;
    wire [WORD_ADDR_W-1:0] rd_word_addr;
    wire                  rd_fifo_word_done;
    reg  [7:0]            rd_pixel_mux;

    assign rd_pixel = rd_pixel_mux;
    assign wr_frame_start = wr_vsync && !wr_vsync_d;
    assign wr_frame_end   = !wr_vsync && wr_vsync_d;
    assign wr_line_end    = wr_vsync && wr_hsync_d && !wr_hsync;
    assign wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    assign wr_x_sample    = wr_x_in_crop && (wr_x_phase != 4'd15);
    assign wr_y_sample    = (wr_y < IR_IN_H) && (wr_y_phase != 4'd15);
    assign wr_sample_now  = wr_vsync && wr_hsync &&
                            wr_x_sample && wr_y_sample &&
                            (wr_addr < FRAME_PIXELS) && !wr_fifo_full;
    assign wr_pixel_above_raw      = wr_prev_line_pixel[wr_x];
    assign wr_left_valid           = (wr_x > CROP_X_START);
    assign wr_pixel_left_eff       = wr_left_valid ? wr_pixel_left : wr_pixel;
    assign wr_pixel_above_eff      = wr_have_prev_line ? wr_pixel_above_raw : wr_pixel;
    assign wr_pixel_above_left_eff = (wr_have_prev_line && wr_left_valid) ? wr_pixel_above_left : wr_pixel_left_eff;
    assign wr_pixel_filtered       = avg4_u8(wr_pixel, wr_pixel_left_eff,
                                             wr_pixel_above_eff, wr_pixel_above_left_eff);
    assign wr_fifo_din    = {(wr_addr == (FRAME_PIXELS - 1)), wr_bank, wr_addr, wr_pixel_filtered};
    assign rd_fifo_pop    = !rd_fifo_empty;
    assign rd_fifo_last   = rd_fifo_dout[FIFO_WIDTH-1];
    assign rd_fifo_bank   = rd_fifo_dout[FIFO_WIDTH-2];
    assign rd_fifo_addr   = rd_fifo_dout[FRAME_ADDR_W+7:8];
    assign rd_fifo_pixel  = rd_fifo_dout[7:0];
    assign rd_fifo_word_addr = rd_fifo_addr[FRAME_ADDR_W-1:3];
    assign rd_word_addr = rd_addr[FRAME_ADDR_W-1:3];
    assign rd_fifo_word_done = rd_fifo_pop && (rd_fifo_addr[2:0] == 3'd7);
    assign rd_word_selected = rd_bank_pipe[READ_LATENCY-1] ? rd_word_buf1 : rd_word_buf0;
    assign rd_byte_selected = rd_byte_pipe[(3*READ_LATENCY)-1 -: 3];

    function [7:0] avg4_u8;
        input [7:0] a;
        input [7:0] b;
        input [7:0] c;
        input [7:0] d;
        reg [9:0] sum;
        begin
            sum = {2'b0, a} + {2'b0, b} + {2'b0, c} + {2'b0, d} + 10'd2;
            avg4_u8 = sum[9:2];
        end
    endfunction

    always @* begin
        pack_word_next = pack_word;
        case (rd_fifo_addr[2:0])
            3'd0: pack_word_next[7:0]   = rd_fifo_pixel;
            3'd1: pack_word_next[15:8]  = rd_fifo_pixel;
            3'd2: pack_word_next[23:16] = rd_fifo_pixel;
            3'd3: pack_word_next[31:24] = rd_fifo_pixel;
            3'd4: pack_word_next[39:32] = rd_fifo_pixel;
            3'd5: pack_word_next[47:40] = rd_fifo_pixel;
            3'd6: pack_word_next[55:48] = rd_fifo_pixel;
            default: pack_word_next[63:56] = rd_fifo_pixel;
        endcase
    end

    always @* begin
        case (rd_byte_selected)
            3'd0: rd_pixel_mux = rd_word_selected[7:0];
            3'd1: rd_pixel_mux = rd_word_selected[15:8];
            3'd2: rd_pixel_mux = rd_word_selected[23:16];
            3'd3: rd_pixel_mux = rd_word_selected[31:24];
            3'd4: rd_pixel_mux = rd_word_selected[39:32];
            3'd5: rd_pixel_mux = rd_word_selected[47:40];
            3'd6: rd_pixel_mux = rd_word_selected[55:48];
            default: rd_pixel_mux = rd_word_selected[63:56];
        endcase
    end

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr           <= {FRAME_ADDR_W{1'b0}};
            wr_bank           <= 1'b0;
            wr_hsync_d        <= 1'b0;
            wr_vsync_d        <= 1'b0;
            wr_x              <= 10'd0;
            wr_y              <= 10'd0;
            wr_x_phase        <= 4'd0;
            wr_y_phase        <= 4'd0;
            wr_have_prev_line <= 1'b0;
            wr_pixel_left     <= 8'd0;
            wr_pixel_above_left <= 8'd0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_addr             <= {FRAME_ADDR_W{1'b0}};
                wr_x                <= 10'd0;
                wr_y                <= 10'd0;
                wr_x_phase          <= 4'd0;
                wr_y_phase          <= 4'd0;
                wr_have_prev_line   <= 1'b0;
                wr_pixel_left       <= 8'd0;
                wr_pixel_above_left <= 8'd0;
            end else begin
                if (wr_vsync && wr_hsync) begin
                    wr_prev_line_pixel[wr_x] <= wr_pixel;
                    wr_pixel_left            <= wr_pixel;
                    wr_pixel_above_left      <= wr_pixel_above_raw;

                    if (wr_x_in_crop) begin
                        if (wr_x_phase == 4'd15)
                            wr_x_phase <= 4'd0;
                        else
                            wr_x_phase <= wr_x_phase + 4'd1;
                    end
                    wr_x <= wr_x + 10'd1;
                end

                if (wr_sample_now)
                    wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};

                if (wr_line_end) begin
                    wr_x                <= 10'd0;
                    wr_x_phase          <= 4'd0;
                    wr_have_prev_line   <= 1'b1;
                    wr_pixel_left       <= 8'd0;
                    wr_pixel_above_left <= 8'd0;
                    if (wr_y < IR_IN_H) begin
                        wr_y <= wr_y + 10'd1;
                        if (wr_y_phase == 4'd15)
                            wr_y_phase <= 4'd0;
                        else
                            wr_y_phase <= wr_y_phase + 4'd1;
                    end
                end
            end

            if (wr_frame_end) begin
                if (wr_addr == FRAME_PIXELS)
                    wr_bank           <= ~wr_bank;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            rd_bank              <= 1'b0;
            pending_bank         <= 1'b0;
            pending_valid        <= 1'b0;
            frame_valid          <= 1'b0;
            rd_bank_pipe         <= {READ_LATENCY{1'b0}};
            rd_byte_pipe         <= {(3*READ_LATENCY){1'b0}};
            pack_word            <= 64'd0;
        end else begin
            rd_bank_pipe        <= {rd_bank_pipe[READ_LATENCY-2:0], rd_bank};
            rd_byte_pipe        <= {rd_byte_pipe[(3*(READ_LATENCY-1))-1:0], rd_addr[2:0]};

            if (rd_fifo_pop)
                pack_word <= pack_word_next;

            if (rd_fifo_pop && rd_fifo_last) begin
                pending_bank         <= rd_fifo_bank;
                pending_valid        <= 1'b1;
            end

            if (rd_frame_start && pending_valid) begin
                rd_bank      <= pending_bank;
                frame_valid  <= 1'b1;
                pending_valid <= 1'b0;
            end
        end
    end

    xpm_fifo_async #(
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("auto"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (1024),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (900),
        .RD_DATA_COUNT_WIDTH (11),
        .READ_DATA_WIDTH     (FIFO_WIDTH),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0000"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (FIFO_WIDTH),
        .WR_DATA_COUNT_WIDTH (11)
    ) u_wr_cdc_fifo (
        .sleep         (1'b0),
        .rst           (~rst_n),
        .wr_clk        (wr_clk),
        .wr_en         (wr_sample_now),
        .din           (wr_fifo_din),
        .full          (wr_fifo_full),
        .overflow      (),
        .wr_rst_busy   (),
        .wr_ack        (),
        .wr_data_count (),
        .almost_full   (),
        .prog_full     (),
        .rd_clk        (rd_clk),
        .rd_en         (rd_fifo_pop),
        .dout          (rd_fifo_dout),
        .empty         (rd_fifo_empty),
        .underflow     (),
        .rd_rst_busy   (),
        .data_valid    (),
        .rd_data_count (),
        .almost_empty  (),
        .prog_empty    (),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
    );

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (WORD_ADDR_W),
        .ADDR_WIDTH_B             (WORD_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (64),
        .CLOCKING_MODE            ("common_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("ultra"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (64),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (64),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf0 (
        .sleep          (1'b0),
        .clka           (rd_clk),
        .ena            (rd_fifo_word_done && (rd_fifo_bank == 1'b0)),
        .wea            (rd_fifo_word_done && (rd_fifo_bank == 1'b0)),
        .addra          (rd_fifo_word_addr),
        .dina           (pack_word_next),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en && (rd_bank == 1'b0)),
        .regceb         (1'b1),
        .addrb          (rd_word_addr),
        .doutb          (rd_word_buf0),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (WORD_ADDR_W),
        .ADDR_WIDTH_B             (WORD_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (64),
        .CLOCKING_MODE            ("common_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("ultra"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (64),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (64),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf1 (
        .sleep          (1'b0),
        .clka           (rd_clk),
        .ena            (rd_fifo_word_done && (rd_fifo_bank == 1'b1)),
        .wea            (rd_fifo_word_done && (rd_fifo_bank == 1'b1)),
        .addra          (rd_fifo_word_addr),
        .dina           (pack_word_next),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en && (rd_bank == 1'b1)),
        .regceb         (1'b1),
        .addrb          (rd_word_addr),
        .doutb          (rd_word_buf1),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule

module IR540x480_GrayFrameBuffer_Single #(
    parameter integer SRC_W        = 540,
    parameter integer SRC_H        = 480,
    parameter integer FRAME_ADDR_W = 18,
    parameter integer READ_LATENCY = 2
)(
    input  wire                    rst_n,
    input  wire                    wr_clk,
    input  wire                    wr_hsync,
    input  wire                    wr_vsync,
    input  wire [7:0]              wr_pixel,
    input  wire                    rd_clk,
    input  wire                    rd_en,
    input  wire [FRAME_ADDR_W-1:0] rd_addr,
    output wire [7:0]              rd_pixel,
    output reg                     frame_valid
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer FRAME_BITS   = FRAME_PIXELS * 8;
    localparam integer IR_IN_H      = 512;
    localparam integer CROP_X_START = 32;
    localparam integer CROP_X_WIDTH = (SRC_W * 16) / 15;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    reg [9:0]              wr_x;
    reg [9:0]              wr_y;
    reg [3:0]              wr_x_phase;
    reg [3:0]              wr_y_phase;
    reg                    wr_en;
    reg                    frame_toggle_wr;
    reg                    frame_toggle_meta;
    reg                    frame_toggle_sync;
    reg                    frame_toggle_sync_d;

    wire wr_frame_start = wr_vsync && !wr_vsync_d;
    wire wr_frame_end   = !wr_vsync && wr_vsync_d;
    wire wr_line_end    = wr_vsync && wr_hsync_d && !wr_hsync;
    wire wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    wire wr_x_sample    = wr_x_in_crop && (wr_x_phase != 4'd15);
    wire wr_y_sample    = (wr_y < IR_IN_H) && (wr_y_phase != 4'd15);
    wire wr_sample_now  = wr_vsync && wr_hsync &&
                          wr_x_sample && wr_y_sample &&
                          (wr_addr < FRAME_PIXELS);

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr         <= {FRAME_ADDR_W{1'b0}};
            wr_hsync_d      <= 1'b0;
            wr_vsync_d      <= 1'b0;
            wr_x            <= 10'd0;
            wr_y            <= 10'd0;
            wr_x_phase      <= 4'd0;
            wr_y_phase      <= 4'd0;
            wr_en           <= 1'b0;
            frame_toggle_wr <= 1'b0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;
            wr_en      <= 1'b0;

            if (wr_frame_start) begin
                wr_addr <= {FRAME_ADDR_W{1'b0}};
                wr_x    <= 10'd0;
                wr_y    <= 10'd0;
                wr_x_phase <= 4'd0;
                wr_y_phase <= 4'd0;
            end else begin
                if (wr_vsync && wr_hsync) begin
                    if (wr_x_in_crop) begin
                        if (wr_x_phase == 4'd15)
                            wr_x_phase <= 4'd0;
                        else
                            wr_x_phase <= wr_x_phase + 4'd1;
                    end
                    wr_x <= wr_x + 10'd1;
                end

                if (wr_sample_now) begin
                    wr_en   <= 1'b1;
                    wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
                end

                if (wr_line_end) begin
                    wr_x       <= 10'd0;
                    wr_x_phase <= 4'd0;
                    if (wr_y < IR_IN_H) begin
                        wr_y <= wr_y + 10'd1;
                        if (wr_y_phase == 4'd15)
                            wr_y_phase <= 4'd0;
                        else
                            wr_y_phase <= wr_y_phase + 4'd1;
                    end
                end
            end

            if (wr_frame_end) begin
                if (wr_addr == FRAME_PIXELS)
                    frame_toggle_wr <= ~frame_toggle_wr;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_toggle_meta   <= 1'b0;
            frame_toggle_sync   <= 1'b0;
            frame_toggle_sync_d <= 1'b0;
            frame_valid         <= 1'b0;
        end else begin
            frame_toggle_meta   <= frame_toggle_wr;
            frame_toggle_sync   <= frame_toggle_meta;
            frame_toggle_sync_d <= frame_toggle_sync;

            if (frame_toggle_sync != frame_toggle_sync_d)
                frame_valid <= 1'b1;
        end
    end

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (8),
        .CLOCKING_MODE            ("independent_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("block"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (8),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (8),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf (
        .sleep          (1'b0),
        .clka           (wr_clk),
        .ena            (wr_en),
        .wea            (wr_en),
        .addra          (wr_addr),
        .dina           (wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_pixel),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule

module IR6Modes_To_HD1080p_Buffered(
    input  wire        rst_n,
    input  wire        rd_clk,
    input  wire        stack_mode,
    input  wire [2:0]  single_sel,
    input  wire        cam0_wr_clk,
    input  wire        cam0_wr_hsync,
    input  wire        cam0_wr_vsync,
    input  wire [7:0]  cam0_wr_pixel,
    input  wire        cam1_wr_clk,
    input  wire        cam1_wr_hsync,
    input  wire        cam1_wr_vsync,
    input  wire [7:0]  cam1_wr_pixel,
    input  wire        cam2_wr_clk,
    input  wire        cam2_wr_hsync,
    input  wire        cam2_wr_vsync,
    input  wire [7:0]  cam2_wr_pixel,
    input  wire        cam3_wr_clk,
    input  wire        cam3_wr_hsync,
    input  wire        cam3_wr_vsync,
    input  wire [7:0]  cam3_wr_pixel,
    input  wire        cam4_wr_clk,
    input  wire        cam4_wr_hsync,
    input  wire        cam4_wr_vsync,
    input  wire [7:0]  cam4_wr_pixel,
    input  wire        cam5_wr_clk,
    input  wire        cam5_wr_hsync,
    input  wire        cam5_wr_vsync,
    input  wire [7:0]  cam5_wr_pixel,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W         = 540;
    localparam integer SRC_H         = 480;
    localparam integer FRAME_ADDR_W  = 18;
    localparam integer READ_LATENCY  = 2;

    localparam integer HD_ACTIVE_W   = 1920;
    localparam integer HD_ACTIVE_H   = 1080;
    localparam integer HD_TOTAL_W    = 2200;
    localparam integer HD_TOTAL_H    = 1125;
    localparam integer SAV_WORDS     = 4;
    localparam integer EAV_WORDS     = 4;
    localparam integer STACK_W       = 3 * SRC_W;
    localparam integer STACK_H       = 2 * SRC_H;
    localparam integer X_OFF         = (HD_ACTIVE_W - SRC_W) / 2;
    localparam integer Y_OFF         = (HD_ACTIVE_H - SRC_H) / 2;
    localparam [19:0]  BT1120_BLACK  = {10'd64, 10'd512};
    localparam [19:0]  ZERO_PAD_BLACK = {10'd0, 10'd512};
    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg [READ_LATENCY-1:0] use_img_pipe;
    reg [3*READ_LATENCY-1:0] cam_pipe;

    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    reg [2:0]  next_cam_idx_r;
    reg [9:0]  next_local_x_r;
    reg [8:0]  next_local_y_r;

    wire [7:0] cam0_rd_pixel, cam1_rd_pixel, cam2_rd_pixel;
    wire [7:0] cam3_rd_pixel, cam4_rd_pixel, cam5_rd_pixel;
    wire       cam0_frame_valid, cam1_frame_valid, cam2_frame_valid;
    wire       cam3_frame_valid, cam4_frame_valid, cam5_frame_valid;

    assign hd_de    = hd_de_r;
    assign hd_hsync = hd_hsync_r;
    assign hd_vsync = hd_vsync_r;
    assign hd_dout  = hd_dout_r;

    wire cur_vblank = (v_cnt >= HD_ACTIVE_H);
    wire cur_sav    = (h_cnt < SAV_WORDS);
    wire cur_active = (h_cnt >= SAV_WORDS) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W)) && (v_cnt < HD_ACTIVE_H);
    wire cur_eav    = (h_cnt >= (SAV_WORDS + HD_ACTIVE_W)) &&
                      (h_cnt <  (SAV_WORDS + HD_ACTIVE_W + EAV_WORDS));

    wire end_line   = (h_cnt == HD_TOTAL_W - 1);
    wire end_frame  = end_line && (v_cnt == HD_TOTAL_H - 1);
    wire [11:0] h_next = end_line ? 12'd0 : (h_cnt + 12'd1);
    wire [10:0] v_next = end_line ? (end_frame ? 11'd0 : (v_cnt + 11'd1)) : v_cnt;
    wire        rd_frame_start = (h_cnt == 12'd0) && (v_cnt == 11'd0);

    wire next_active = (h_next >= SAV_WORDS) && (h_next < (SAV_WORDS + HD_ACTIVE_W)) && (v_next < HD_ACTIVE_H);
    wire [11:0] next_x = h_next - SAV_WORDS;
    wire [10:0] next_y = v_next;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire        next_inside_stack = next_active && (next_x < STACK_W) && (next_y < STACK_H);
    wire        next_inside_single = next_active &&
                                     (next_x >= X_OFF) && (next_x < (X_OFF + SRC_W)) &&
                                     (next_y >= Y_OFF) && (next_y < (Y_OFF + SRC_H));
    wire        next_inside_image = stack_mode ? next_inside_stack : next_inside_single;

    wire [FRAME_ADDR_W-1:0] next_img_addr =
        (next_local_y_r * SRC_W) + next_local_x_r;

    wire selected_frame_valid =
        (next_cam_idx_r == 3'd0) ? cam0_frame_valid :
        (next_cam_idx_r == 3'd1) ? cam1_frame_valid :
        (next_cam_idx_r == 3'd2) ? cam2_frame_valid :
        (next_cam_idx_r == 3'd3) ? cam3_frame_valid :
        (next_cam_idx_r == 3'd4) ? cam4_frame_valid :
                                   cam5_frame_valid;

    wire next_use_img = next_inside_image && selected_frame_valid;

    wire cam0_rd_en = next_use_img && (next_cam_idx_r == 3'd0);
    wire cam1_rd_en = next_use_img && (next_cam_idx_r == 3'd1);
    wire cam2_rd_en = next_use_img && (next_cam_idx_r == 3'd2);
    wire cam3_rd_en = next_use_img && (next_cam_idx_r == 3'd3);
    wire cam4_rd_en = next_use_img && (next_cam_idx_r == 3'd4);
    wire cam5_rd_en = next_use_img && (next_cam_idx_r == 3'd5);

    wire [2:0] cur_cam_idx = cam_pipe[(3*READ_LATENCY)-1 -: 3];
    wire [7:0] stack_pixel =
        (cur_cam_idx == 3'd0) ? cam0_rd_pixel :
        (cur_cam_idx == 3'd1) ? cam1_rd_pixel :
        (cur_cam_idx == 3'd2) ? cam2_rd_pixel :
        (cur_cam_idx == 3'd3) ? cam3_rd_pixel :
        (cur_cam_idx == 3'd4) ? cam4_rd_pixel :
                                cam5_rd_pixel;

    always @* begin
        next_cam_idx_r = 3'd0;
        next_local_x_r = 10'd0;
        next_local_y_r = 9'd0;

        if (stack_mode) begin
            if (next_inside_stack) begin
                if (next_y < SRC_H) begin
                    next_local_y_r = next_y[8:0];
                    if (next_x < SRC_W) begin
                        next_cam_idx_r = 3'd0;
                        next_local_x_r = next_x[9:0];
                    end else if (next_x < (2*SRC_W)) begin
                        next_cam_idx_r = 3'd1;
                        next_local_x_r = next_x - SRC_W;
                    end else begin
                        next_cam_idx_r = 3'd2;
                        next_local_x_r = next_x - (2*SRC_W);
                    end
                end else begin
                    next_local_y_r = next_y - SRC_H;
                    if (next_x < SRC_W) begin
                        next_cam_idx_r = 3'd3;
                        next_local_x_r = next_x[9:0];
                    end else if (next_x < (2*SRC_W)) begin
                        next_cam_idx_r = 3'd4;
                        next_local_x_r = next_x - SRC_W;
                    end else begin
                        next_cam_idx_r = 3'd5;
                        next_local_x_r = next_x - (2*SRC_W);
                    end
                end
            end
        end else begin
            next_cam_idx_r = single_sel;
            if (next_inside_single) begin
                next_local_x_r = next_x - X_OFF;
                next_local_y_r = next_y - Y_OFF;
            end
        end
    end

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1,
                         f_bit,
                         v_bit,
                         h_bit,
                         (v_bit ^ h_bit),
                         (f_bit ^ h_bit),
                         (f_bit ^ v_bit),
                         (f_bit ^ v_bit ^ h_bit)};
        end
    endfunction

    function [19:0] bt1120_trs_word;
        input [1:0] idx;
        input       f_bit;
        input       v_bit;
        input       h_bit;
        reg [7:0] xy;
        begin
            xy = bt1120_xy(f_bit, v_bit, h_bit);
            case (idx)
                2'd0: bt1120_trs_word = {10'h3FF, 10'h3FF};
                2'd1: bt1120_trs_word = {10'h000, 10'h000};
                2'd2: bt1120_trs_word = {10'h000, 10'h000};
                default: bt1120_trs_word = {{xy, 2'b00}, {xy, 2'b00}};
            endcase
        end
    endfunction

    IR540x480_GrayFrameBuffer u_cam0_fb (
        .rst_n         (rst_n), .wr_clk(cam0_wr_clk), .wr_hsync(cam0_wr_hsync), .wr_vsync(cam0_wr_vsync), .wr_pixel(cam0_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam0_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam0_rd_pixel), .frame_valid(cam0_frame_valid)
    );
    IR540x480_GrayFrameBuffer u_cam1_fb (
        .rst_n         (rst_n), .wr_clk(cam1_wr_clk), .wr_hsync(cam1_wr_hsync), .wr_vsync(cam1_wr_vsync), .wr_pixel(cam1_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam1_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam1_rd_pixel), .frame_valid(cam1_frame_valid)
    );
    IR540x480_GrayFrameBuffer u_cam2_fb (
        .rst_n         (rst_n), .wr_clk(cam2_wr_clk), .wr_hsync(cam2_wr_hsync), .wr_vsync(cam2_wr_vsync), .wr_pixel(cam2_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam2_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam2_rd_pixel), .frame_valid(cam2_frame_valid)
    );
    IR540x480_GrayFrameBuffer u_cam3_fb (
        .rst_n         (rst_n), .wr_clk(cam3_wr_clk), .wr_hsync(cam3_wr_hsync), .wr_vsync(cam3_wr_vsync), .wr_pixel(cam3_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam3_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam3_rd_pixel), .frame_valid(cam3_frame_valid)
    );
    IR540x480_GrayFrameBuffer u_cam4_fb (
        .rst_n         (rst_n), .wr_clk(cam4_wr_clk), .wr_hsync(cam4_wr_hsync), .wr_vsync(cam4_wr_vsync), .wr_pixel(cam4_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam4_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam4_rd_pixel), .frame_valid(cam4_frame_valid)
    );
    IR540x480_GrayFrameBuffer u_cam5_fb (
        .rst_n         (rst_n), .wr_clk(cam5_wr_clk), .wr_hsync(cam5_wr_hsync), .wr_vsync(cam5_wr_vsync), .wr_pixel(cam5_wr_pixel),
        .rd_clk        (rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam5_rd_en), .rd_addr(next_img_addr),
        .rd_pixel      (cam5_rd_pixel), .frame_valid(cam5_frame_valid)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt       <= 12'd0;
            v_cnt       <= 11'd0;
            use_img_pipe<= {READ_LATENCY{1'b0}};
            cam_pipe    <= {3*READ_LATENCY{1'b0}};
            hd_de_r     <= 1'b0;
            hd_hsync_r  <= 1'b0;
            hd_vsync_r  <= 1'b0;
            hd_dout_r   <= BT1120_BLACK;
        end else begin
            use_img_pipe <= {use_img_pipe[READ_LATENCY-2:0], next_use_img};
            cam_pipe     <= {cam_pipe[(3*(READ_LATENCY-1))-1:0], next_cam_idx_r};

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav) begin
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            end else if (cur_eav) begin
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            end else if (cur_active) begin
                if (use_img_pipe[READ_LATENCY-1])
                    hd_dout_r <= {{stack_pixel, 2'b00}, 10'd512};
                else
                    hd_dout_r <= ZERO_PAD_BLACK;
            end else begin
                hd_dout_r <= BT1120_BLACK;
            end

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module IR540x480_To_HD1080p_Buffered(
    input  wire        rst_n,
    input  wire        wr_clk,
    input  wire        wr_hsync,
    input  wire        wr_vsync,
    input  wire [7:0]  wr_pixel,
    input  wire        rd_clk,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W         = 540;
    localparam integer SRC_H         = 480;
    localparam integer FRAME_PIXELS  = SRC_W * SRC_H;
    localparam integer FRAME_ADDR_W  = 18;   // ceil(log2(259200))
    localparam integer FRAME_BITS    = FRAME_PIXELS * 8;
    localparam integer READ_LATENCY  = 2;
    localparam integer IR_IN_H       = 512;
    localparam integer CROP_X_START  = 32;
    localparam integer CROP_X_WIDTH  = (SRC_W * 16) / 15;
    localparam integer CROP_X_END    = CROP_X_START + CROP_X_WIDTH;

    localparam integer HD_ACTIVE_W   = 1920;
    localparam integer HD_ACTIVE_H   = 1080;
    localparam integer HD_TOTAL_W    = 2200;
    localparam integer HD_TOTAL_H    = 1125;
    localparam integer SAV_WORDS     = 4;
    localparam integer EAV_WORDS     = 4;
    localparam integer X_OFF         = (HD_ACTIVE_W - SRC_W) / 2; // 690
    localparam integer Y_OFF         = (HD_ACTIVE_H - SRC_H) / 2; // 300

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_bank;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    reg [9:0]              wr_x;
    reg [9:0]              wr_y;
    reg [3:0]              wr_x_phase;
    reg [3:0]              wr_y_phase;
    reg                    frame_toggle_wr;
    reg                    completed_bank_wr;
    reg                    wr_en_buf0;
    reg                    wr_en_buf1;

    wire wr_frame_start = wr_vsync && !wr_vsync_d;
    wire wr_frame_end   = !wr_vsync && wr_vsync_d;
    wire wr_line_end    = wr_vsync && wr_hsync_d && !wr_hsync;
    wire wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    wire wr_x_sample    = wr_x_in_crop && (wr_x_phase != 4'd15);
    wire wr_y_sample    = (wr_y < IR_IN_H) && (wr_y_phase != 4'd15);
    wire wr_sample_now  = wr_vsync && wr_hsync &&
                          wr_x_sample && wr_y_sample &&
                          (wr_addr < FRAME_PIXELS);

    // Capture the 540x480 left/top crop from the selected IR active region.
    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr           <= {FRAME_ADDR_W{1'b0}};
            wr_bank           <= 1'b0;
            wr_hsync_d        <= 1'b0;
            wr_vsync_d        <= 1'b0;
            wr_x              <= 10'd0;
            wr_y              <= 10'd0;
            wr_x_phase        <= 4'd0;
            wr_y_phase        <= 4'd0;
            frame_toggle_wr   <= 1'b0;
            completed_bank_wr <= 1'b0;
            wr_en_buf0        <= 1'b0;
            wr_en_buf1        <= 1'b0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;
            wr_en_buf0 <= 1'b0;
            wr_en_buf1 <= 1'b0;

            if (wr_frame_start) begin
                wr_addr <= {FRAME_ADDR_W{1'b0}};
                wr_x    <= 10'd0;
                wr_y    <= 10'd0;
                wr_x_phase <= 4'd0;
                wr_y_phase <= 4'd0;
            end else begin
                if (wr_vsync && wr_hsync) begin
                    if (wr_x_in_crop) begin
                        if (wr_x_phase == 4'd15)
                            wr_x_phase <= 4'd0;
                        else
                            wr_x_phase <= wr_x_phase + 4'd1;
                    end
                    wr_x <= wr_x + 10'd1;
                end

                if (wr_sample_now) begin
                    if (wr_bank == 1'b0)
                        wr_en_buf0 <= 1'b1;
                    else
                        wr_en_buf1 <= 1'b1;
                    wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
                end

                if (wr_line_end) begin
                    wr_x       <= 10'd0;
                    wr_x_phase <= 4'd0;
                    if (wr_y < IR_IN_H) begin
                        wr_y <= wr_y + 10'd1;
                        if (wr_y_phase == 4'd15)
                            wr_y_phase <= 4'd0;
                        else
                            wr_y_phase <= wr_y_phase + 4'd1;
                    end
                end
            end

            if (wr_frame_end) begin
                if (wr_addr == FRAME_PIXELS) begin
                    completed_bank_wr <= wr_bank;
                    frame_toggle_wr   <= ~frame_toggle_wr;
                    wr_bank           <= ~wr_bank;
                end
            end
        end
    end

    // Synchronize completed-frame notification into the HD read clock domain.
    reg frame_toggle_meta, frame_toggle_sync, frame_toggle_sync_d;
    reg completed_bank_meta, completed_bank_sync;
    reg rd_bank;
    reg frame_valid;
    reg capture_bank_pending;
    reg pending_bank;
    reg pending_valid;
    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg [READ_LATENCY-1:0] use_img_pipe;
    reg [READ_LATENCY-1:0] rd_bank_pipe;
    wire [7:0] rd_pixel_buf0;
    wire [7:0] rd_pixel_buf1;
    wire [7:0] rd_pixel_q;

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_toggle_meta   <= 1'b0;
            frame_toggle_sync   <= 1'b0;
            frame_toggle_sync_d <= 1'b0;
            completed_bank_meta <= 1'b0;
            completed_bank_sync <= 1'b0;
            rd_bank             <= 1'b0;
            frame_valid         <= 1'b0;
            capture_bank_pending<= 1'b0;
            pending_bank        <= 1'b0;
            pending_valid       <= 1'b0;
        end else begin
            frame_toggle_meta   <= frame_toggle_wr;
            frame_toggle_sync   <= frame_toggle_meta;
            frame_toggle_sync_d <= frame_toggle_sync;
            completed_bank_meta <= completed_bank_wr;
            completed_bank_sync <= completed_bank_meta;

            if (frame_toggle_sync != frame_toggle_sync_d) begin
                capture_bank_pending <= 1'b1;
            end

            if (capture_bank_pending) begin
                pending_bank         <= completed_bank_sync;
                pending_valid        <= 1'b1;
                capture_bank_pending <= 1'b0;
            end

            // Only switch the displayed frame at the HD frame boundary.
            if ((h_cnt == 12'd0) && (v_cnt == 11'd0) && pending_valid) begin
                rd_bank     <= pending_bank;
                frame_valid <= 1'b1;
                pending_valid <= 1'b0;
            end
        end
    end

    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    assign hd_de    = hd_de_r;
    assign hd_hsync = hd_hsync_r;
    assign hd_vsync = hd_vsync_r;
    assign hd_dout  = hd_dout_r;

    wire cur_vblank = (v_cnt >= HD_ACTIVE_H);
    wire cur_sav    = (h_cnt < SAV_WORDS);
    wire cur_active = (h_cnt >= SAV_WORDS) && (h_cnt < (SAV_WORDS + HD_ACTIVE_W)) && (v_cnt < HD_ACTIVE_H);
    wire cur_eav    = (h_cnt >= (SAV_WORDS + HD_ACTIVE_W)) &&
                      (h_cnt <  (SAV_WORDS + HD_ACTIVE_W + EAV_WORDS));

    wire end_line  = (h_cnt == HD_TOTAL_W - 1);
    wire end_frame = end_line && (v_cnt == HD_TOTAL_H - 1);
    wire [11:0] h_next = end_line ? 12'd0 : (h_cnt + 12'd1);
    wire [10:0] v_next = end_line ? (end_frame ? 11'd0 : (v_cnt + 11'd1)) : v_cnt;

    wire next_active = (h_next >= SAV_WORDS) && (h_next < (SAV_WORDS + HD_ACTIVE_W)) && (v_next < HD_ACTIVE_H);
    wire [11:0] next_x = h_next - SAV_WORDS;
    wire [10:0] next_y = v_next;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);

    wire next_inside_image = next_active && frame_valid &&
                             (next_x >= X_OFF) && (next_x < (X_OFF + SRC_W)) &&
                             (next_y >= Y_OFF) && (next_y < (Y_OFF + SRC_H));

    wire [FRAME_ADDR_W-1:0] next_img_addr =
        ((next_y - Y_OFF) * SRC_W) + (next_x - X_OFF);

    assign rd_pixel_q = rd_bank_pipe[READ_LATENCY-1] ? rd_pixel_buf1 : rd_pixel_buf0;

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1,
                         f_bit,
                         v_bit,
                         h_bit,
                         (v_bit ^ h_bit),
                         (f_bit ^ h_bit),
                         (f_bit ^ v_bit),
                         (f_bit ^ v_bit ^ h_bit)};
        end
    endfunction

    function [19:0] bt1120_trs_word;
        input [1:0] idx;
        input       f_bit;
        input       v_bit;
        input       h_bit;
        reg [7:0] xy;
        begin
            xy = bt1120_xy(f_bit, v_bit, h_bit);
            case (idx)
                2'd0: bt1120_trs_word = {10'h3FF, 10'h3FF};
                2'd1: bt1120_trs_word = {10'h000, 10'h000};
                2'd2: bt1120_trs_word = {10'h000, 10'h000};
                default: bt1120_trs_word = {{xy, 2'b00}, {xy, 2'b00}};
            endcase
        end
    endfunction

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (8),
        .CLOCKING_MODE            ("independent_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("block"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (8),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (8),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf0 (
        .sleep          (1'b0),
        .clka           (wr_clk),
        .ena            (wr_en_buf0),
        .wea            (wr_en_buf0),
        .addra          (wr_addr),
        .dina           (wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (next_inside_image && (rd_bank == 1'b0)),
        .regceb         (1'b1),
        .addrb          (next_img_addr),
        .doutb          (rd_pixel_buf0),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (8),
        .CLOCKING_MODE            ("independent_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("block"),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (8),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (8),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf1 (
        .sleep          (1'b0),
        .clka           (wr_clk),
        .ena            (wr_en_buf1),
        .wea            (wr_en_buf1),
        .addra          (wr_addr),
        .dina           (wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (next_inside_image && (rd_bank == 1'b1)),
        .regceb         (1'b1),
        .addrb          (next_img_addr),
        .doutb          (rd_pixel_buf1),
        .sbiterrb       (),
        .dbiterrb       ()
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            use_img_pipe <= {READ_LATENCY{1'b0}};
            rd_bank_pipe <= {READ_LATENCY{1'b0}};
        end else begin
            use_img_pipe <= {use_img_pipe[READ_LATENCY-2:0], next_inside_image};
            rd_bank_pipe <= {rd_bank_pipe[READ_LATENCY-2:0], rd_bank};
        end
    end

    // Generate a 1920x1080 BT.1120-style raster in the HD clock domain.
    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt     <= 12'd0;
            v_cnt     <= 11'd0;
            hd_de_r   <= 1'b0;
            hd_hsync_r<= 1'b0;
            hd_vsync_r<= 1'b0;
            hd_dout_r <= {10'd64, 10'd512};
        end else begin
            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav) begin
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            end else if (cur_eav) begin
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            end else if (cur_active) begin
                if (use_img_pipe[READ_LATENCY-1])
                    hd_dout_r <= {{rd_pixel_q, 2'b00}, 10'd512};
                else
                    hd_dout_r <= {10'd64, 10'd512};
            end else begin
                hd_dout_r <= {10'd64, 10'd512};
            end

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module Kintex_top_I2C_test #(
    parameter [6:0] SLAVE_ADDR = 7'h36,

    // ===== Internal POR reset params =====
    parameter integer SCLK_HZ = 100_000_000, // 100 MHz default
    parameter integer POR_MS  = 100,         // 100 ms reset

    parameter integer REG_COUNT = 128
)(
    input  wire FPGA_RESET, // unused
    input  wire SCLK_IN,
    input  wire SCL,
    inout  wire SDA,
    input  wire [127:0] debug_status,
	output wire [3:0] cam_select,
    output wire [7:0] mode_out
);

    //===========================================================
    // SCLK BUFG
    //===========================================================
    wire SCLK;
    BUFG u_bufg_sclk (
        .I (SCLK_IN),
        .O (SCLK)
    );

    //===========================================================
    // Internal POR reset (POR_MS)
    //===========================================================
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction

    localparam integer POR_CYCLES = (SCLK_HZ * POR_MS) / 1000;
    localparam integer POR_W      = (POR_CYCLES <= 1) ? 1 : clog2(POR_CYCLES + 1);

    reg  [POR_W-1:0] por_cnt /* synthesis preserve */;
    wire             nRESET_INT;

    assign nRESET_INT = (POR_CYCLES <= 1) ? 1'b1
                                          : (por_cnt >= POR_CYCLES[POR_W-1:0]);

    always @(posedge SCLK) begin
        if (!nRESET_INT)
            por_cnt <= por_cnt + 1'b1;
    end

    //===========================================================
    // IBUF for SCL
    //===========================================================
    wire scl_ibuf;
    IBUF u_ibuf_scl (
        .I(SCL),
        .O(scl_ibuf)
    );

    //===========================================================
    // IOBUF for SDA (Open-Drain: low only)
    //===========================================================
    reg  sda_oe;     // 1 => drive LOW, 0 => release(Z)
    wire sda_in;

    wire sda_i;
    wire sda_o;
    wire sda_t;

    assign sda_o = 1'b0;
    assign sda_t = ~sda_oe;

    IOBUF u_iobuf_sda (
        .I (sda_o),
        .O (sda_i),
        .T (sda_t),
        .IO(SDA)
    );

    assign sda_in = sda_i;

    //===========================================================
    // Sync SCL and SDA to SCLK
    //===========================================================
    reg scl_meta, scl_sync, scl_sync_d;
    reg sda_meta, sda_sync, sda_sync_d;

    wire scl_rise =  scl_sync & ~scl_sync_d;
    wire scl_fall = ~scl_sync &  scl_sync_d;

    wire sda_rise =  sda_sync & ~sda_sync_d;
    wire sda_fall = ~sda_sync &  sda_sync_d;

    // ---- START/STOP qualification to avoid false detection ----
    wire scl_high_qual = scl_meta & scl_sync; // stable HIGH only

    wire start_cond = sda_fall & scl_high_qual; // START: SDA fall while SCL=1
    wire stop_cond  = sda_rise & scl_high_qual; // STOP : SDA rise while SCL=1

    //===========================================================
    // Register file (128 x 8-bit)
    // Force flip-flop/register implementation instead of inferred RAM.
    // The old known-good design used a small discrete register bank; once
    // expanded to 128 bytes we must prevent BRAM/LUTRAM inference so random
    // 8-bit address accesses continue to behave as a simple byte register file.
    //===========================================================
    (* ram_style = "registers" *) reg [7:0] regfile [0:REG_COUNT-1];
    localparam [7:0] DEFAULT_MODE = 8'h15; // EO stack

    // Power-on (configuration-time) INIT of the register file. Vivado bakes
    // these values into the flop INIT bits, so regfile[0] comes up as EO stack
    // the instant the FPGA finishes configuration -- before the async POR reset
    // logic runs and before the host MCU writes anything over I2C. Combined with
    // the reset-branch assignment below, the boot image is EO_Stack regardless
    // of reset/host timing.
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < REG_COUNT; init_idx = init_idx + 1)
            regfile[init_idx] = 8'h00;
        regfile[8'h00] = DEFAULT_MODE;
    end

    reg [7:0] reg_index;
    reg [7:0] read_data_byte;

    wire [7:0] mode_reg = regfile[8'h00];
    assign mode_out = mode_reg;
    wire [31:0] eo_cyl_h_fov_q16 = {regfile[8'h23], regfile[8'h22], regfile[8'h21], regfile[8'h20]};
    wire [31:0] eo_cyl_v_fov_q16 = {regfile[8'h27], regfile[8'h26], regfile[8'h25], regfile[8'h24]};
    wire [31:0] eo_crop_h_q16    = {regfile[8'h2B], regfile[8'h2A], regfile[8'h29], regfile[8'h28]};
    wire [31:0] eo_crop_w_q16    = {regfile[8'h2F], regfile[8'h2E], regfile[8'h2D], regfile[8'h2C]};
    wire [31:0] eo_pitch_tr_q16  = {regfile[8'h33], regfile[8'h32], regfile[8'h31], regfile[8'h30]};
    wire [31:0] eo_yaw_tr_q16    = {regfile[8'h37], regfile[8'h36], regfile[8'h35], regfile[8'h34]};
    wire [31:0] eo_overlap_i32   = {regfile[8'h3B], regfile[8'h3A], regfile[8'h39], regfile[8'h38]};
    wire [31:0] eo_feather_q16   = {regfile[8'h3F], regfile[8'h3E], regfile[8'h3D], regfile[8'h3C]};

    wire [31:0] ir_cyl_h_fov_q16 = {regfile[8'h53], regfile[8'h52], regfile[8'h51], regfile[8'h50]};
    wire [31:0] ir_cyl_v_fov_q16 = {regfile[8'h57], regfile[8'h56], regfile[8'h55], regfile[8'h54]};
    wire [31:0] ir_crop_h_q16    = {regfile[8'h5B], regfile[8'h5A], regfile[8'h59], regfile[8'h58]};
    wire [31:0] ir_crop_w_q16    = {regfile[8'h5F], regfile[8'h5E], regfile[8'h5D], regfile[8'h5C]};
    wire [31:0] ir_pitch_tr_q16  = {regfile[8'h63], regfile[8'h62], regfile[8'h61], regfile[8'h60]};
    wire [31:0] ir_yaw_tr_q16    = {regfile[8'h67], regfile[8'h66], regfile[8'h65], regfile[8'h64]};
    wire [31:0] ir_overlap_i32   = {regfile[8'h6B], regfile[8'h6A], regfile[8'h69], regfile[8'h68]};
    wire [31:0] ir_feather_q16   = {regfile[8'h6F], regfile[8'h6E], regfile[8'h6D], regfile[8'h6C]};
    assign cam_select =
        (mode_reg <= 8'd5)                      ? mode_reg[3:0] :
        ((mode_reg >= 8'h0D) && (mode_reg <= 8'h12)) ? (mode_reg - 8'h0D) :
                                                  4'd0;

    always @* begin
        case (reg_index)
            8'h70: read_data_byte = debug_status[7:0];
            8'h71: read_data_byte = debug_status[15:8];
            8'h72: read_data_byte = debug_status[23:16];
            8'h73: read_data_byte = debug_status[31:24];
            8'h74: read_data_byte = debug_status[39:32];
            8'h75: read_data_byte = debug_status[47:40];
            8'h76: read_data_byte = debug_status[55:48];
            8'h77: read_data_byte = debug_status[63:56];
            8'h78: read_data_byte = debug_status[71:64];
            8'h79: read_data_byte = debug_status[79:72];
            8'h7A: read_data_byte = debug_status[87:80];
            8'h7B: read_data_byte = debug_status[95:88];
            8'h7C: read_data_byte = debug_status[103:96];
            8'h7D: read_data_byte = debug_status[111:104];
            8'h7E: read_data_byte = debug_status[119:112];
            8'h7F: read_data_byte = debug_status[127:120];
            default: read_data_byte = regfile[reg_index];
        endcase
    end

    //===========================================================
    // FSM / Shifters
    //===========================================================
    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_ADDR_RX   = 4'd1,
        ST_ADDR_ACK  = 4'd2,
        ST_REG_RX    = 4'd3,
        ST_REG_ACK   = 4'd4,
        ST_WRITE_RX  = 4'd5,
        ST_WRITE_ACK = 4'd6,
        ST_READ_TX   = 4'd7,
        ST_READ_ACK  = 4'd8;

    reg [3:0] state;
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg;
    reg       rw_flag; // 0=write, 1=read
    reg       addr_match;
    integer   idx;

    //===========================================================
    // Debug signals (ILA)
    //===========================================================
     /*
     wire dbg_sclk    = SCLK;
     wire dbg_rstn    = nRESET_INT;
     wire dbg_scl     = scl_ibuf;
     wire dbg_sda     = sda_in;
     wire dbg_sclsync = scl_sync;
     wire dbg_sdasyn  = sda_sync;
     wire dbg_start   = start_cond;
     wire dbg_stop    = stop_cond;
     wire dbg_sclr    = scl_rise;
     wire dbg_sclf    = scl_fall;
     wire dbg_sdaoe   = sda_oe;

     reg  [3:0] dbg_state;
     reg  [2:0] dbg_bit_cnt;
     reg  [7:0] dbg_shift_reg;
     reg  [3:0] dbg_reg_index;
     reg        dbg_addr_match;
     reg        dbg_rw;

    // Write debug mirrors (ILA friendly)
     reg [3:0] dbg_last_wr_idx;
     reg [7:0] dbg_last_wr_data;
     reg       dbg_last_wr_pulse;

    always @(posedge SCLK) begin
        dbg_state      <= state;
        dbg_bit_cnt    <= bit_cnt;
        dbg_shift_reg  <= shift_reg;
        dbg_reg_index  <= reg_index;
        dbg_addr_match <= addr_match;
        dbg_rw         <= rw_flag;
    end
    */

    //===========================================================
    // Input synchronizers
    //===========================================================
    always @(posedge SCLK or negedge nRESET_INT) begin
        if (!nRESET_INT) begin
            scl_meta   <= 1'b0;
            scl_sync   <= 1'b0;
            scl_sync_d <= 1'b0;

            sda_meta   <= 1'b1;
            sda_sync   <= 1'b1;
            sda_sync_d <= 1'b1;
        end else begin
            scl_meta   <= scl_ibuf;
            scl_sync   <= scl_meta;
            scl_sync_d <= scl_sync;

            sda_meta   <= sda_in;
            sda_sync   <= sda_meta;
            sda_sync_d <= sda_sync;
        end
    end

    //===========================================================
    // Main FSM (RX on SCL rising, drive SDA only while SCL low)
    //===========================================================
    always @(posedge SCLK or negedge nRESET_INT) begin
        if (!nRESET_INT) begin
            state      <= ST_IDLE;
            bit_cnt    <= 3'd0;
            shift_reg  <= 8'd0;
            rw_flag    <= 1'b0;
            addr_match <= 1'b0;
            reg_index  <= 8'd0;

            for (idx = 0; idx < REG_COUNT; idx = idx + 1)
                regfile[idx] <= 8'h00;
            regfile[8'h00] <= DEFAULT_MODE;

            sda_oe <= 1'b0;

            //dbg_last_wr_idx   <= 4'd0;
            //dbg_last_wr_data  <= 8'd0;
            //dbg_last_wr_pulse <= 1'b0;

        end else begin
            // default pulse low (one-shot)
            //dbg_last_wr_pulse <= 1'b0;

            // STOP: release bus, go idle
            if (stop_cond) begin
                state      <= ST_IDLE;
                sda_oe     <= 1'b0;
                addr_match <= 1'b0;
            end

            // START or Re-START: go receive address
            if (start_cond) begin
                state      <= ST_ADDR_RX;
                bit_cnt    <= 3'd7;
                shift_reg  <= 8'd0;
                sda_oe     <= 1'b0;
                addr_match <= 1'b0;
            end

            // DRIVE SDA only while SCL LOW (ACK / READ data)
            if (!scl_sync) begin
                case (state)
                    ST_ADDR_ACK:  sda_oe <= addr_match ? 1'b1 : 1'b0;
                    ST_REG_ACK:   sda_oe <= addr_match ? 1'b1 : 1'b0;
                    ST_WRITE_ACK: sda_oe <= addr_match ? 1'b1 : 1'b0;

                    ST_READ_TX: begin
                        if (!addr_match)
                            sda_oe <= 1'b0;
                        else
                            // open-drain: 0 drives low, 1 releases
                            sda_oe <= (read_data_byte[bit_cnt] == 1'b0) ? 1'b1 : 1'b0;
                    end

                    ST_READ_ACK:  sda_oe <= 1'b0; // master drives ACK/NACK

                    default:      sda_oe <= 1'b0; // RX states: release
                endcase
            end

            // SAMPLE on SCL rising edge
            if (scl_rise) begin
                case (state)

                    ST_ADDR_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            // address bits already in shift_reg[7:1]
                            rw_flag    <= sda_sync;                 // R/W bit
                            addr_match <= (shift_reg[7:1] == SLAVE_ADDR); // Verilog-safe
                            state      <= ST_ADDR_ACK;
                            bit_cnt    <= 3'd7;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_ADDR_ACK: begin
                        if (!addr_match) begin
                            state <= ST_IDLE;
                        end else if (rw_flag == 1'b0) begin
                            state     <= ST_REG_RX;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            state   <= ST_READ_TX;
                            bit_cnt <= 3'd7;
                        end
                    end

                    ST_REG_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            reg_index <= {shift_reg[7:1], sda_sync};
                            state     <= ST_REG_ACK;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_REG_ACK: begin
                        state     <= ST_WRITE_RX;
                        bit_cnt   <= 3'd7;
                        shift_reg <= 8'd0;
                    end

                    ST_WRITE_RX: begin
                        shift_reg[bit_cnt] <= sda_sync;
                        if (bit_cnt == 0) begin
                            // WRITE the received data byte
                            regfile[reg_index] <= {shift_reg[7:1], sda_sync};

                            // Debug mirrors (confirm actual write happened)
                            //dbg_last_wr_idx   <= reg_index;
                            //dbg_last_wr_data  <= {shift_reg[7:1], sda_sync};
                            //dbg_last_wr_pulse <= 1'b1;

                            reg_index <= reg_index + 1'b1;
                            state     <= ST_WRITE_ACK;
                            bit_cnt   <= 3'd7;
                            shift_reg <= 8'd0;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_WRITE_ACK: begin
                        state     <= ST_WRITE_RX;
                        bit_cnt   <= 3'd7;
                        shift_reg <= 8'd0;
                    end

                    ST_READ_TX: begin
                        if (!addr_match) begin
                            state <= ST_IDLE;
                        end else if (bit_cnt == 0) begin
                            state <= ST_READ_ACK;
                        end else begin
                            bit_cnt <= bit_cnt - 1'b1;
                        end
                    end

                    ST_READ_ACK: begin
                        if (sda_sync == 1'b0) begin
                            reg_index <= reg_index + 1'b1;
                            state     <= ST_READ_TX;
                            bit_cnt   <= 3'd7;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end

                    default: begin
                        state <= ST_IDLE;
                    end
                endcase
            end
        end
    end
 

endmodule
