module EO1920x1080_Decimate3_FrameBuffer #(
    parameter integer SRC_W        = 640,
    parameter integer SRC_H        = 480,
    parameter integer FRAME_ADDR_W = 19,
    parameter integer READ_LATENCY = 2,
    parameter        CLOCKING_MODE_STR = "common_clock",
    parameter        MEMORY_PRIMITIVE_STR = "block",
    parameter integer FIFO_RELATED_CLOCKS = 0,
    parameter integer USE_ASYNC_FIFO = 1
)(
    input  wire                     rst_n,
    input  wire                     wr_clk,
    input  wire                     wr_hsync,
    input  wire                     wr_vsync,
    input  wire [19:0]              wr_pixel,
    input  wire                     rd_clk,
    input  wire                     rd_frame_start,
    input  wire                     rd_en,
    input  wire [FRAME_ADDR_W-1:0]  rd_addr,
    output wire [19:0]              rd_pixel,
    output reg                      frame_valid
);
    localparam integer FRAME_PIXELS = SRC_W * SRC_H;
    localparam integer PACKED_PIXEL_W = 16;
    localparam integer FRAME_BITS   = FRAME_PIXELS * PACKED_PIXEL_W;
    localparam integer FIFO_WIDTH   = 1 + FRAME_ADDR_W + PACKED_PIXEL_W;
    localparam integer CROP_X_START = 240;
    localparam integer CROP_X_WIDTH = (SRC_W * 9) / 4;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg [FRAME_ADDR_W-1:0] wr_addr;
    reg                    wr_hsync_d;
    reg                    wr_vsync_d;
    reg [11:0]             wr_x;
    reg [3:0]              wr_x_phase;
    reg [3:0]              wr_y_phase;
    wire                   wr_frame_active;
    wire                   wr_frame_start;
    wire                   wr_line_end;
    wire                   wr_fifo_full;
    wire                   wr_sample_now;
    wire                   wr_x_in_crop;
    wire                   wr_x_sample;
    wire                   wr_y_sample;
    wire [FIFO_WIDTH-1:0]  wr_fifo_din;
    wire                   mem_wr_en;
    wire [FRAME_ADDR_W-1:0] mem_wr_addr;
    wire [PACKED_PIXEL_W-1:0] mem_wr_pixel;
    wire                   frame_complete_rd;
    wire [PACKED_PIXEL_W-1:0] wr_pixel_packed;

    assign wr_pixel_packed = {wr_pixel[19:12], wr_pixel[9:2]};
    assign wr_frame_active = ~wr_vsync;
    assign wr_frame_start  = wr_vsync_d && ~wr_vsync;
    assign wr_line_end     = wr_hsync_d && ~wr_hsync && wr_frame_active;
    assign wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    // Select whole Y/C chroma pairs so the stacked output keeps Cb/Cr cadence.
    assign wr_x_sample    = wr_x_in_crop &&
                            ((wr_x_phase == 4'd0) || (wr_x_phase == 4'd2) ||
                             (wr_x_phase == 4'd4) || (wr_x_phase == 4'd6));
    assign wr_y_sample    = (wr_y_phase == 4'd0) || (wr_y_phase == 4'd2) ||
                            (wr_y_phase == 4'd4) || (wr_y_phase == 4'd6);
    assign wr_sample_now   = wr_frame_active && wr_hsync &&
                             wr_y_sample && wr_x_sample &&
                             (wr_addr < FRAME_PIXELS) && !wr_fifo_full;
    assign wr_fifo_din     = {(wr_addr == (FRAME_PIXELS - 1)), wr_addr, wr_pixel_packed};

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_addr           <= {FRAME_ADDR_W{1'b0}};
            wr_hsync_d        <= 1'b0;
            wr_vsync_d        <= 1'b0;
            wr_x              <= 12'd0;
            wr_x_phase        <= 4'd0;
            wr_y_phase        <= 4'd0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_addr     <= {FRAME_ADDR_W{1'b0}};
                wr_x        <= 12'd0;
                wr_x_phase  <= 4'd0;
                wr_y_phase <= 4'd0;
            end

            if (wr_frame_active && wr_hsync) begin
                if (wr_sample_now) begin
                    wr_addr <= wr_addr + {{(FRAME_ADDR_W-1){1'b0}}, 1'b1};
                end

                if (wr_x_in_crop && wr_x[0]) begin
                    if (wr_x_phase == 4'd8)
                        wr_x_phase <= 4'd0;
                    else
                        wr_x_phase <= wr_x_phase + 4'd1;
                end

                wr_x <= wr_x + 12'd1;
            end

            if (wr_line_end) begin
                wr_x       <= 12'd0;
                wr_x_phase <= 4'd0;
                if (wr_y_phase == 4'd8)
                    wr_y_phase <= 4'd0;
                else
                    wr_y_phase <= wr_y_phase + 4'd1;
            end
        end
    end

    wire [PACKED_PIXEL_W-1:0] rd_pixel_buf;
    assign rd_pixel = {rd_pixel_buf[15:8], 2'b00, rd_pixel_buf[7:0], 2'b00};

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            frame_valid <= 1'b0;
        end else begin
            if (frame_complete_rd)
                frame_valid <= 1'b1;
        end
    end

    generate
        if (USE_ASYNC_FIFO) begin : gen_async_wr
            wire [FIFO_WIDTH-1:0] rd_fifo_dout;
            wire                  rd_fifo_empty;
            wire                  rd_fifo_pop;
            wire                  rd_fifo_last;
            wire [FRAME_ADDR_W-1:0] rd_fifo_addr;
            wire [PACKED_PIXEL_W-1:0] rd_fifo_pixel;
            wire                  wr_fifo_full_i;

            assign rd_fifo_pop     = !rd_fifo_empty;
            assign rd_fifo_last    = rd_fifo_dout[FIFO_WIDTH-1];
            assign rd_fifo_addr    = rd_fifo_dout[FRAME_ADDR_W+PACKED_PIXEL_W-1:PACKED_PIXEL_W];
            assign rd_fifo_pixel   = rd_fifo_dout[PACKED_PIXEL_W-1:0];
            assign wr_fifo_full    = wr_fifo_full_i;
            assign mem_wr_en       = rd_fifo_pop;
            assign mem_wr_addr     = rd_fifo_addr;
            assign mem_wr_pixel    = rd_fifo_pixel;
            assign frame_complete_rd = rd_fifo_pop && rd_fifo_last;

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
                .RELATED_CLOCKS      (FIFO_RELATED_CLOCKS),
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
                .full          (wr_fifo_full_i),
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
        end else begin : gen_direct_wr
            assign wr_fifo_full      = 1'b0;
            assign mem_wr_en         = wr_sample_now;
            assign mem_wr_addr       = wr_addr;
            assign mem_wr_pixel      = wr_pixel_packed;
            assign frame_complete_rd = wr_sample_now && (wr_addr == (FRAME_PIXELS - 1));
        end
    endgenerate

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (FRAME_ADDR_W),
        .ADDR_WIDTH_B             (FRAME_ADDR_W),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (PACKED_PIXEL_W),
        .CLOCKING_MODE            (CLOCKING_MODE_STR),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         (MEMORY_PRIMITIVE_STR),
        .MEMORY_SIZE              (FRAME_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (PACKED_PIXEL_W),
        .READ_LATENCY_B           (READ_LATENCY),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (PACKED_PIXEL_W),
        .WRITE_MODE_B             ("read_first")
    ) u_framebuf (
        .sleep          (1'b0),
        .clka           (rd_clk),
        .ena            (mem_wr_en),
        .wea            (mem_wr_en),
        .addra          (mem_wr_addr),
        .dina           (mem_wr_pixel),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (~rst_n),
        .enb            (rd_en),
        .regceb         (1'b1),
        .addrb          (rd_addr),
        .doutb          (rd_pixel_buf),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule

module EO6Stack_To_HD1080p_Buffered(
    input  wire        rst_n,
    input  wire        rd_clk,
    input  wire        cam0_wr_clk,
    input  wire        cam0_wr_hsync,
    input  wire        cam0_wr_vsync,
    input  wire [19:0] cam0_wr_pixel,
    input  wire        cam1_wr_clk,
    input  wire        cam1_wr_hsync,
    input  wire        cam1_wr_vsync,
    input  wire [19:0] cam1_wr_pixel,
    input  wire        cam2_wr_clk,
    input  wire        cam2_wr_hsync,
    input  wire        cam2_wr_vsync,
    input  wire [19:0] cam2_wr_pixel,
    input  wire        cam3_wr_clk,
    input  wire        cam3_wr_hsync,
    input  wire        cam3_wr_vsync,
    input  wire [19:0] cam3_wr_pixel,
    input  wire        cam4_wr_clk,
    input  wire        cam4_wr_hsync,
    input  wire        cam4_wr_vsync,
    input  wire [19:0] cam4_wr_pixel,
    input  wire        cam5_wr_clk,
    input  wire        cam5_wr_hsync,
    input  wire        cam5_wr_vsync,
    input  wire [19:0] cam5_wr_pixel,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W         = 640;
    localparam integer SRC_H         = 480;
    localparam integer FRAME_ADDR_W  = 19;
    localparam integer READ_LATENCY  = 2;

    localparam integer HD_ACTIVE_W   = 1920;
    localparam integer HD_ACTIVE_H   = 1080;
    localparam integer HD_TOTAL_W    = 2200;
    localparam integer HD_TOTAL_H    = 1125;
    localparam integer SAV_WORDS     = 4;
    localparam integer EAV_WORDS     = 4;
    localparam integer STACK_H       = 960;

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

    wire [19:0] cam0_rd_pixel, cam1_rd_pixel, cam2_rd_pixel;
    wire [19:0] cam3_rd_pixel, cam4_rd_pixel, cam5_rd_pixel;
    wire        cam0_frame_valid, cam1_frame_valid, cam2_frame_valid;
    wire        cam3_frame_valid, cam4_frame_valid, cam5_frame_valid;

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
    wire        next_inside_stack = next_active && (next_y < STACK_H);

    wire [FRAME_ADDR_W-1:0] next_img_addr =
        (next_local_y_r * SRC_W) + next_local_x_r;

    wire selected_frame_valid =
        (next_cam_idx_r == 3'd0) ? cam0_frame_valid :
        (next_cam_idx_r == 3'd1) ? cam1_frame_valid :
        (next_cam_idx_r == 3'd2) ? cam2_frame_valid :
        (next_cam_idx_r == 3'd3) ? cam3_frame_valid :
        (next_cam_idx_r == 3'd4) ? cam4_frame_valid :
                                   cam5_frame_valid;

    wire next_use_img = next_inside_stack && selected_frame_valid;

    wire cam0_rd_en = next_use_img && (next_cam_idx_r == 3'd0);
    wire cam1_rd_en = next_use_img && (next_cam_idx_r == 3'd1);
    wire cam2_rd_en = next_use_img && (next_cam_idx_r == 3'd2);
    wire cam3_rd_en = next_use_img && (next_cam_idx_r == 3'd3);
    wire cam4_rd_en = next_use_img && (next_cam_idx_r == 3'd4);
    wire cam5_rd_en = next_use_img && (next_cam_idx_r == 3'd5);

    wire [2:0] cur_cam_idx = cam_pipe[(3*READ_LATENCY)-1 -: 3];
    wire [19:0] stack_pixel =
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

    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY), .CLOCKING_MODE_STR("common_clock"), .FIFO_RELATED_CLOCKS(1), .USE_ASYNC_FIFO(0)) u_eo_fb0 (
        .rst_n(rst_n), .wr_clk(cam0_wr_clk), .wr_hsync(cam0_wr_hsync), .wr_vsync(cam0_wr_vsync), .wr_pixel(cam0_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam0_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam0_rd_pixel), .frame_valid(cam0_frame_valid)
    );
    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY)) u_eo_fb1 (
        .rst_n(rst_n), .wr_clk(cam1_wr_clk), .wr_hsync(cam1_wr_hsync), .wr_vsync(cam1_wr_vsync), .wr_pixel(cam1_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam1_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam1_rd_pixel), .frame_valid(cam1_frame_valid)
    );
    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY)) u_eo_fb2 (
        .rst_n(rst_n), .wr_clk(cam2_wr_clk), .wr_hsync(cam2_wr_hsync), .wr_vsync(cam2_wr_vsync), .wr_pixel(cam2_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam2_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam2_rd_pixel), .frame_valid(cam2_frame_valid)
    );
    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY)) u_eo_fb3 (
        .rst_n(rst_n), .wr_clk(cam3_wr_clk), .wr_hsync(cam3_wr_hsync), .wr_vsync(cam3_wr_vsync), .wr_pixel(cam3_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam3_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam3_rd_pixel), .frame_valid(cam3_frame_valid)
    );
    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY)) u_eo_fb4 (
        .rst_n(rst_n), .wr_clk(cam4_wr_clk), .wr_hsync(cam4_wr_hsync), .wr_vsync(cam4_wr_vsync), .wr_pixel(cam4_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam4_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam4_rd_pixel), .frame_valid(cam4_frame_valid)
    );
    EO1920x1080_Decimate3_FrameBuffer #(.SRC_W(SRC_W), .SRC_H(SRC_H), .FRAME_ADDR_W(FRAME_ADDR_W), .READ_LATENCY(READ_LATENCY)) u_eo_fb5 (
        .rst_n(rst_n), .wr_clk(cam5_wr_clk), .wr_hsync(cam5_wr_hsync), .wr_vsync(cam5_wr_vsync), .wr_pixel(cam5_wr_pixel),
        .rd_clk(rd_clk), .rd_frame_start(rd_frame_start), .rd_en(cam5_rd_en), .rd_addr(next_img_addr),
        .rd_pixel(cam5_rd_pixel), .frame_valid(cam5_frame_valid)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            use_img_pipe <= {READ_LATENCY{1'b0}};
            cam_pipe     <= {(3*READ_LATENCY){1'b0}};
        end else begin
            use_img_pipe <= {use_img_pipe[READ_LATENCY-2:0], next_use_img};
            cam_pipe     <= {cam_pipe[(3*(READ_LATENCY-1))-1:0], next_cam_idx_r};
        end
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt      <= 12'd0;
            v_cnt      <= 11'd0;
            hd_de_r    <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r  <= {10'd64, 10'd512};
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
                    hd_dout_r <= stack_pixel;
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
