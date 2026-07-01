module AsyncUramFwftFifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 16
)(
    input  wire                  rst,
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,
    input  wire                  rd_clk,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  empty,
    output wire [ADDR_WIDTH:0]   rd_data_count
);
    localparam integer PTR_WIDTH = ADDR_WIDTH + 1;
    localparam integer MEMORY_SIZE_BITS = DATA_WIDTH * (1 << ADDR_WIDTH);

    function [PTR_WIDTH-1:0] bin2gray;
        input [PTR_WIDTH-1:0] bin;
        begin
            bin2gray = (bin >> 1) ^ bin;
        end
    endfunction

    function [PTR_WIDTH-1:0] gray2bin;
        input [PTR_WIDTH-1:0] gray;
        integer i;
        begin
            gray2bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                gray2bin[i] = gray2bin[i+1] ^ gray[i];
        end
    endfunction

    reg [PTR_WIDTH-1:0] wr_bin;
    reg [PTR_WIDTH-1:0] wr_gray;
    reg [PTR_WIDTH-1:0] rd_commit_gray_wr1;
    reg [PTR_WIDTH-1:0] rd_commit_gray_wr2;

    reg [PTR_WIDTH-1:0] rd_req_bin;
    reg [PTR_WIDTH-1:0] rd_commit_bin;
    reg [PTR_WIDTH-1:0] rd_commit_gray;
    reg [PTR_WIDTH-1:0] wr_gray_rd1;
    reg [PTR_WIDTH-1:0] wr_gray_rd2;
    reg [1:0]           rd_valid_pipe;
    reg [1:0]           q_count;
    reg [DATA_WIDTH-1:0] q0;
    reg [DATA_WIDTH-1:0] q1;
    reg                  mem_rd_en;
    reg [ADDR_WIDTH-1:0] mem_rd_addr;

    wire [PTR_WIDTH-1:0] wr_bin_rd = gray2bin(wr_gray_rd2);
    wire [PTR_WIDTH-1:0] wr_bin_plus1 = wr_bin + {{ADDR_WIDTH{1'b0}}, 1'b1};
    wire [PTR_WIDTH-1:0] wr_gray_plus1 = bin2gray(wr_bin_plus1);
    wire [PTR_WIDTH-1:0] wr_bin_next = (wr_en && !full) ? wr_bin_plus1 : wr_bin;
    wire [PTR_WIDTH-1:0] wr_gray_next = (wr_en && !full) ? wr_gray_plus1 : wr_gray;
    wire [PTR_WIDTH-1:0] rd_req_avail = wr_bin_rd - rd_req_bin;
    wire [2:0] buffered_words = {1'b0, q_count} +
                                {2'b00, rd_valid_pipe[0]} +
                                {2'b00, rd_valid_pipe[1]};
    wire       can_issue_read = (rd_req_avail != {PTR_WIDTH{1'b0}}) &&
                                (buffered_words < 3'd2);
    wire       queue_pop = rd_en && (q_count != 2'd0);
    wire       mem_resp_valid = rd_valid_pipe[1];
    wire [DATA_WIDTH-1:0] mem_dout;

    assign full = (wr_gray_plus1 == {~rd_commit_gray_wr2[PTR_WIDTH-1:PTR_WIDTH-2],
                                     rd_commit_gray_wr2[PTR_WIDTH-3:0]});
    assign empty = (q_count == 2'd0);
    assign dout = q0;
    assign rd_data_count = wr_bin_rd - rd_commit_bin;

    always @(posedge wr_clk) begin
        if (rst) begin
            wr_bin             <= {PTR_WIDTH{1'b0}};
            wr_gray            <= {PTR_WIDTH{1'b0}};
            rd_commit_gray_wr1 <= {PTR_WIDTH{1'b0}};
            rd_commit_gray_wr2 <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_commit_gray_wr1 <= rd_commit_gray;
            rd_commit_gray_wr2 <= rd_commit_gray_wr1;

            if (wr_en && !full) begin
                wr_bin  <= wr_bin_next;
                wr_gray <= wr_gray_next;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (rst) begin
            rd_req_bin     <= {PTR_WIDTH{1'b0}};
            rd_commit_bin  <= {PTR_WIDTH{1'b0}};
            rd_commit_gray <= {PTR_WIDTH{1'b0}};
            wr_gray_rd1    <= {PTR_WIDTH{1'b0}};
            wr_gray_rd2    <= {PTR_WIDTH{1'b0}};
            rd_valid_pipe  <= 2'b00;
            q_count        <= 2'd0;
            q0             <= {DATA_WIDTH{1'b0}};
            q1             <= {DATA_WIDTH{1'b0}};
            mem_rd_en      <= 1'b0;
            mem_rd_addr    <= {ADDR_WIDTH{1'b0}};
        end else begin
            wr_gray_rd1 <= wr_gray;
            wr_gray_rd2 <= wr_gray_rd1;

            mem_rd_en <= can_issue_read;
            if (can_issue_read) begin
                mem_rd_addr <= rd_req_bin[ADDR_WIDTH-1:0];
                rd_req_bin  <= rd_req_bin + {{ADDR_WIDTH{1'b0}}, 1'b1};
            end

            rd_valid_pipe <= {rd_valid_pipe[0], can_issue_read};

            case ({mem_resp_valid, queue_pop})
                2'b01: begin
                    if (q_count == 2'd2)
                        q0 <= q1;
                    q_count <= q_count - 2'd1;
                end
                2'b10: begin
                    if (q_count == 2'd0)
                        q0 <= mem_dout;
                    else
                        q1 <= mem_dout;
                    q_count <= q_count + 2'd1;
                end
                2'b11: begin
                    if (q_count == 2'd1) begin
                        q0 <= mem_dout;
                        q_count <= 2'd1;
                    end else begin
                        q0 <= q1;
                        q1 <= mem_dout;
                        q_count <= q_count;
                    end
                end
                default: begin
                    q_count <= q_count;
                end
            endcase

            if (mem_resp_valid) begin
                rd_commit_bin  <= rd_commit_bin + {{ADDR_WIDTH{1'b0}}, 1'b1};
                rd_commit_gray <= bin2gray(rd_commit_bin + {{ADDR_WIDTH{1'b0}}, 1'b1});
            end
        end
    end

    xpm_memory_sdpram #(
        .ADDR_WIDTH_A             (ADDR_WIDTH),
        .ADDR_WIDTH_B             (ADDR_WIDTH),
        .AUTO_SLEEP_TIME          (0),
        .BYTE_WRITE_WIDTH_A       (DATA_WIDTH),
        .CLOCKING_MODE            ("independent_clock"),
        .ECC_MODE                 ("no_ecc"),
        .MEMORY_INIT_FILE         ("none"),
        .MEMORY_INIT_PARAM        ("0"),
        .MEMORY_OPTIMIZATION      ("true"),
        .MEMORY_PRIMITIVE         ("ultra"),
        .MEMORY_SIZE              (MEMORY_SIZE_BITS),
        .MESSAGE_CONTROL          (0),
        .READ_DATA_WIDTH_B        (DATA_WIDTH),
        .READ_LATENCY_B           (2),
        .READ_RESET_VALUE_B       ("0"),
        .RST_MODE_B               ("SYNC"),
        .SIM_ASSERT_CHK           (0),
        .USE_EMBEDDED_CONSTRAINT  (0),
        .USE_MEM_INIT             (1),
        .WAKEUP_TIME              ("disable_sleep"),
        .WRITE_DATA_WIDTH_A       (DATA_WIDTH),
        .WRITE_MODE_B             ("read_first")
    ) u_mem (
        .sleep          (1'b0),
        .clka           (wr_clk),
        .ena            (wr_en && !full),
        .wea            (wr_en && !full),
        .addra          (wr_bin[ADDR_WIDTH-1:0]),
        .dina           (din),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .clkb           (rd_clk),
        .rstb           (rst),
        .enb            (mem_rd_en),
        .regceb         (1'b1),
        .addrb          (mem_rd_addr),
        .doutb          (mem_dout),
        .sbiterrb       (),
        .dbiterrb       ()
    );
endmodule

module AsyncToSyncUramFwftFifo #(
    parameter integer DATA_WIDTH = 64,
    parameter integer ADDR_WIDTH = 16
)(
    input  wire                  rst,
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire                  full,
    input  wire                  rd_clk,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire                  empty,
    output wire [ADDR_WIDTH:0]   rd_data_count
);
    localparam integer STORE_DEPTH = (1 << ADDR_WIDTH);
    localparam integer CDC_DEPTH   = 2048;
    localparam integer CDC_COUNT_W = 12;

    wire [DATA_WIDTH-1:0] cdc_dout;
    wire                  cdc_empty;
    wire                  cdc_full;
    wire [DATA_WIDTH-1:0] store_dout;
    wire                  store_empty;
    wire                  store_full;
    wire                  move_word = !cdc_empty && !store_full;

    assign full  = cdc_full;
    assign empty = store_empty;
    assign dout  = store_dout;

    xpm_fifo_async #(
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (CDC_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (CDC_DEPTH - 16),
        .RD_DATA_COUNT_WIDTH (CDC_COUNT_W),
        .READ_DATA_WIDTH     (DATA_WIDTH),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0000"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH (CDC_COUNT_W)
    ) u_cdc_fifo (
        .sleep         (1'b0),
        .rst           (rst),
        .wr_clk        (wr_clk),
        .wr_en         (wr_en && !cdc_full),
        .din           (din),
        .full          (cdc_full),
        .overflow      (),
        .wr_rst_busy   (),
        .wr_ack        (),
        .wr_data_count (),
        .almost_full   (),
        .prog_full     (),
        .rd_clk        (rd_clk),
        .rd_en         (move_word),
        .dout          (cdc_dout),
        .empty         (cdc_empty),
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

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("ultra"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (STORE_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (STORE_DEPTH - 1024),
        .RD_DATA_COUNT_WIDTH (ADDR_WIDTH + 1),
        .READ_DATA_WIDTH     (DATA_WIDTH),
        .READ_MODE           ("fwft"),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (DATA_WIDTH),
        .WR_DATA_COUNT_WIDTH (ADDR_WIDTH + 1)
    ) u_store_fifo (
        .sleep         (1'b0),
        .rst           (rst),
        .wr_clk        (rd_clk),
        .wr_en         (move_word),
        .din           (cdc_dout),
        .full          (store_full),
        .overflow      (),
        .wr_rst_busy   (),
        .wr_ack        (),
        .wr_data_count (),
        .almost_full   (),
        .prog_full     (),
        .rd_en         (rd_en && !store_empty),
        .dout          (store_dout),
        .empty         (store_empty),
        .underflow     (),
        .rd_rst_busy   (),
        .data_valid    (),
        .rd_data_count (rd_data_count),
        .almost_empty  (),
        .prog_empty    (),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
    );
endmodule

module EO1920x1080_Decimate_LineFifo #(
    parameter integer FIFO_WRITE_DEPTH = 524288,
    parameter integer FIFO_COUNT_W     = 18,
    parameter         FIFO_MEMORY_TYPE_STR = "block",
    parameter integer FIFO_RELATED_CLOCKS = 0,
    parameter integer USE_ASYNC_FIFO   = 1,
    parameter integer USE_URAM_FIFO    = 0
)(
    input  wire        rst_n,
    input  wire        wr_clk,
    input  wire        wr_hsync,
    input  wire        wr_vsync,
    input  wire [19:0] wr_pixel,
    input  wire        rd_clk,
    input  wire        rd_en,
    output wire [19:0] rd_pixel,
    output wire        rd_empty,
    output wire [19:0] rd_level
);
    localparam integer PIXEL_WIDTH  = 16;
    localparam integer FIFO_WIDTH   = 64;
    localparam integer FIFO_WORD_DEPTH = FIFO_WRITE_DEPTH / 4;
    localparam integer CROP_X_START = 240;
    localparam integer CROP_X_WIDTH = (640 * 9) / 4;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg        wr_hsync_d;
    reg        wr_vsync_d;
    reg [11:0] wr_x;
    reg [3:0]  wr_x_phase;
    reg [3:0]  wr_y_phase;
    reg [47:0] wr_pack_word;
    reg [1:0]  wr_pack_phase;
    reg [1:0]  rd_unpack_phase;

    wire wr_frame_active = ~wr_vsync;
    wire wr_frame_start  = wr_vsync_d && ~wr_vsync;
    wire wr_line_end     = wr_hsync_d && ~wr_hsync && wr_frame_active;
    wire wr_x_in_crop    = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    wire wr_x_sample     = wr_x_in_crop &&
                           ((wr_x_phase == 4'd0) || (wr_x_phase == 4'd2) ||
                            (wr_x_phase == 4'd4) || (wr_x_phase == 4'd6));
    wire wr_y_sample     = (wr_y_phase == 4'd0) || (wr_y_phase == 4'd2) ||
                           (wr_y_phase == 4'd4) || (wr_y_phase == 4'd6);
    wire wr_sample_now   = wr_frame_active && wr_hsync && wr_y_sample && wr_x_sample;
    wire [PIXEL_WIDTH-1:0] wr_fifo_pixel = {wr_pixel[19:12], wr_pixel[9:2]};
    wire [FIFO_WIDTH-1:0]  wr_fifo_din = {wr_fifo_pixel, wr_pack_word};
    wire [FIFO_WIDTH-1:0] rd_fifo_dout;
    wire [FIFO_COUNT_W-1:0] rd_count_i;
    wire fifo_full;
    wire wr_fifo_push = wr_sample_now && !fifo_full && (wr_pack_phase == 2'd3);
    wire rd_fifo_pop  = rd_en && !rd_empty && (rd_unpack_phase == 2'd3);
    wire [PIXEL_WIDTH-1:0] rd_fifo_pixel =
        (rd_unpack_phase == 2'd0) ? rd_fifo_dout[15:0] :
        (rd_unpack_phase == 2'd1) ? rd_fifo_dout[31:16] :
        (rd_unpack_phase == 2'd2) ? rd_fifo_dout[47:32] :
                                    rd_fifo_dout[63:48];

    assign rd_pixel = {rd_fifo_pixel[15:8], 2'b00, rd_fifo_pixel[7:0], 2'b00};

    assign rd_level = {{(20-FIFO_COUNT_W){1'b0}}, rd_count_i} << 2;

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_hsync_d <= 1'b0;
            wr_vsync_d <= 1'b0;
            wr_x       <= 12'd0;
            wr_x_phase <= 4'd0;
            wr_y_phase <= 4'd0;
            wr_pack_word  <= 48'd0;
            wr_pack_phase <= 2'd0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_x       <= 12'd0;
                wr_x_phase <= 4'd0;
                wr_y_phase <= 4'd0;
                wr_pack_word  <= 48'd0;
                wr_pack_phase <= 2'd0;
            end

            if (wr_sample_now && !fifo_full) begin
                case (wr_pack_phase)
                    2'd0: wr_pack_word[15:0]   <= wr_fifo_pixel;
                    2'd1: wr_pack_word[31:16]  <= wr_fifo_pixel;
                    2'd2: wr_pack_word[47:32]  <= wr_fifo_pixel;
                    default: wr_pack_word       <= 48'd0;
                endcase
                wr_pack_phase <= wr_pack_phase + 2'd1;
            end

            if (wr_frame_active && wr_hsync) begin
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
                wr_pack_word  <= 48'd0;
                wr_pack_phase <= 2'd0;
                if (wr_y_phase == 4'd8)
                    wr_y_phase <= 4'd0;
                else
                    wr_y_phase <= wr_y_phase + 4'd1;
            end
        end
    end

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            rd_unpack_phase <= 2'd0;
        end else if (rd_en && !rd_empty) begin
            rd_unpack_phase <= rd_unpack_phase + 2'd1;
        end
    end

    generate
        if (USE_ASYNC_FIFO && USE_URAM_FIFO) begin : gen_async_uram_fifo
            AsyncToSyncUramFwftFifo #(
                .DATA_WIDTH (FIFO_WIDTH),
                .ADDR_WIDTH (FIFO_COUNT_W - 1)
            ) u_fifo (
                .rst           (~rst_n),
                .wr_clk        (wr_clk),
                .wr_en         (wr_fifo_push),
                .din           (wr_fifo_din),
                .full          (fifo_full),
                .rd_clk        (rd_clk),
                .rd_en         (rd_fifo_pop),
                .dout          (rd_fifo_dout),
                .empty         (rd_empty),
                .rd_data_count (rd_count_i)
            );
        end else if (USE_ASYNC_FIFO) begin : gen_async_fifo
            xpm_fifo_async #(
                .CDC_SYNC_STAGES     (2),
                .DOUT_RESET_VALUE    ("0"),
                .ECC_MODE            ("no_ecc"),
                .FIFO_MEMORY_TYPE    (FIFO_MEMORY_TYPE_STR),
                .FIFO_READ_LATENCY   (0),
                .FIFO_WRITE_DEPTH    (FIFO_WORD_DEPTH),
                .FULL_RESET_VALUE    (0),
                .PROG_EMPTY_THRESH   (10),
                .PROG_FULL_THRESH    (FIFO_WORD_DEPTH - 1024),
                .RD_DATA_COUNT_WIDTH (FIFO_COUNT_W),
                .READ_DATA_WIDTH     (FIFO_WIDTH),
                .READ_MODE           ("fwft"),
                .RELATED_CLOCKS      (FIFO_RELATED_CLOCKS),
                .SIM_ASSERT_CHK      (0),
                .USE_ADV_FEATURES    ("0707"),
                .WAKEUP_TIME         (0),
                .WRITE_DATA_WIDTH    (FIFO_WIDTH),
                .WR_DATA_COUNT_WIDTH (FIFO_COUNT_W)
            ) u_fifo (
                .sleep         (1'b0),
                .rst           (~rst_n),
                .wr_clk        (wr_clk),
                .wr_en         (wr_fifo_push),
                .din           (wr_fifo_din),
                .full          (fifo_full),
                .overflow      (),
                .wr_rst_busy   (),
                .wr_ack        (),
                .wr_data_count (),
                .almost_full   (),
                .prog_full     (),
                .rd_clk        (rd_clk),
                .rd_en         (rd_fifo_pop),
                .dout          (rd_fifo_dout),
                .empty         (rd_empty),
                .underflow     (),
                .rd_rst_busy   (),
                .data_valid    (),
                .rd_data_count (rd_count_i),
                .almost_empty  (),
                .prog_empty    (),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (),
                .dbiterr       ()
            );
        end else begin : gen_sync_fifo
            xpm_fifo_sync #(
                .DOUT_RESET_VALUE    ("0"),
                .ECC_MODE            ("no_ecc"),
                .FIFO_MEMORY_TYPE    (FIFO_MEMORY_TYPE_STR),
                .FIFO_READ_LATENCY   (0),
                .FIFO_WRITE_DEPTH    (FIFO_WORD_DEPTH),
                .FULL_RESET_VALUE    (0),
                .PROG_EMPTY_THRESH   (10),
                .PROG_FULL_THRESH    (FIFO_WORD_DEPTH - 1024),
                .RD_DATA_COUNT_WIDTH (FIFO_COUNT_W),
                .READ_DATA_WIDTH     (FIFO_WIDTH),
                .READ_MODE           ("fwft"),
                .SIM_ASSERT_CHK      (0),
                .USE_ADV_FEATURES    ("0707"),
                .WAKEUP_TIME         (0),
                .WRITE_DATA_WIDTH    (FIFO_WIDTH),
                .WR_DATA_COUNT_WIDTH (FIFO_COUNT_W)
            ) u_fifo (
                .sleep         (1'b0),
                .rst           (~rst_n),
                .wr_clk        (rd_clk),
                .wr_en         (wr_fifo_push),
                .din           (wr_fifo_din),
                .full          (fifo_full),
                .overflow      (),
                .wr_rst_busy   (),
                .wr_ack        (),
                .wr_data_count (),
                .almost_full   (),
                .prog_full     (),
                .rd_en         (rd_fifo_pop),
                .dout          (rd_fifo_dout),
                .empty         (rd_empty),
                .underflow     (),
                .rd_rst_busy   (),
                .data_valid    (),
                .rd_data_count (rd_count_i),
                .almost_empty  (),
                .prog_empty    (),
                .injectsbiterr (1'b0),
                .injectdbiterr (1'b0),
                .sbiterr       (),
                .dbiterr       ()
            );
        end
    endgenerate
endmodule

module IR540x480_LineFifo #(
    parameter integer FIFO_WRITE_DEPTH = 262144,
    parameter integer FIFO_COUNT_W     = 19,
    parameter         FIFO_MEMORY_TYPE_STR = "block"
)(
    input  wire       rst_n,
    input  wire       wr_clk,
    input  wire       wr_hsync,
    input  wire       wr_vsync,
    input  wire [7:0] wr_pixel,
    input  wire       rd_clk,
    input  wire       rd_en,
    output wire [7:0] rd_pixel,
    output wire       rd_empty,
    output wire [18:0] rd_level
);
    localparam integer FIFO_WIDTH   = 8;
    localparam integer IR_IN_H      = 512;
    localparam integer CROP_X_START = 32;
    localparam integer CROP_X_WIDTH = (540 * 16) / 15;
    localparam integer CROP_X_END   = CROP_X_START + CROP_X_WIDTH;

    reg        wr_hsync_d;
    reg        wr_vsync_d;
    reg [9:0]  wr_x;
    reg [9:0]  wr_y;
    reg [3:0]  wr_x_phase;
    reg [3:0]  wr_y_phase;

    wire wr_frame_start = wr_vsync && !wr_vsync_d;
    wire wr_line_end    = wr_vsync && wr_hsync_d && !wr_hsync;
    wire wr_x_in_crop   = (wr_x >= CROP_X_START) && (wr_x < CROP_X_END);
    wire wr_x_sample    = wr_x_in_crop && (wr_x_phase != 4'd15);
    wire wr_y_sample    = (wr_y < IR_IN_H) && (wr_y_phase != 4'd15);
    wire wr_sample_now  = wr_vsync && wr_hsync && wr_x_sample && wr_y_sample;
    wire [FIFO_COUNT_W-1:0] rd_count_i;
    wire fifo_full;

    assign rd_pixel = rd_fifo_dout;

    generate
        if (FIFO_COUNT_W == 19) begin : gen_count_full
            assign rd_level = rd_count_i;
        end else begin : gen_count_extend
            assign rd_level = {{(19-FIFO_COUNT_W){1'b0}}, rd_count_i};
        end
    endgenerate

    wire [FIFO_WIDTH-1:0] rd_fifo_dout;

    always @(posedge wr_clk) begin
        if (!rst_n) begin
            wr_hsync_d <= 1'b0;
            wr_vsync_d <= 1'b0;
            wr_x       <= 10'd0;
            wr_y       <= 10'd0;
            wr_x_phase <= 4'd0;
            wr_y_phase <= 4'd0;
        end else begin
            wr_hsync_d <= wr_hsync;
            wr_vsync_d <= wr_vsync;

            if (wr_frame_start) begin
                wr_x       <= 10'd0;
                wr_y       <= 10'd0;
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
        end
    end

    xpm_fifo_async #(
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    (FIFO_MEMORY_TYPE_STR),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (FIFO_WRITE_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (FIFO_WRITE_DEPTH - 1024),
        .RD_DATA_COUNT_WIDTH (FIFO_COUNT_W),
        .READ_DATA_WIDTH     (FIFO_WIDTH),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (FIFO_WIDTH),
        .WR_DATA_COUNT_WIDTH (FIFO_COUNT_W)
    ) u_fifo (
        .sleep         (1'b0),
        .rst           (~rst_n),
        .wr_clk        (wr_clk),
        .wr_en         (wr_sample_now && !fifo_full),
        .din           (wr_pixel),
        .full          (fifo_full),
        .overflow      (),
        .wr_rst_busy   (),
        .wr_ack        (),
        .wr_data_count (),
        .almost_full   (),
        .prog_full     (),
        .rd_clk        (rd_clk),
        .rd_en         (rd_en && !rd_empty),
        .dout          (rd_fifo_dout),
        .empty         (rd_empty),
        .underflow     (),
        .rd_rst_busy   (),
        .data_valid    (),
        .rd_data_count (rd_count_i),
        .almost_empty  (),
        .prog_empty    (),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
    );
endmodule

module EO1920x1080_LineFifo #(
    parameter integer FIFO_WRITE_DEPTH = 16384,
    parameter integer FIFO_COUNT_W     = 15
)(
    input  wire        rst_n,
    input  wire        wr_clk,
    input  wire        wr_hsync,
    input  wire        wr_vsync,
    input  wire [19:0] wr_pixel,
    input  wire        rd_clk,
    input  wire        rd_en,
    output wire [19:0] rd_pixel,
    output wire        rd_empty,
    output wire [19:0] rd_level
);
    wire [FIFO_COUNT_W-1:0] rd_count_i;
    wire fifo_full;

    assign rd_level = {{(20-FIFO_COUNT_W){1'b0}}, rd_count_i};

    xpm_fifo_async #(
        .CDC_SYNC_STAGES     (2),
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (FIFO_WRITE_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (FIFO_WRITE_DEPTH - 1024),
        .RD_DATA_COUNT_WIDTH (FIFO_COUNT_W),
        .READ_DATA_WIDTH     (20),
        .READ_MODE           ("fwft"),
        .RELATED_CLOCKS      (0),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WRITE_DATA_WIDTH    (20),
        .WR_DATA_COUNT_WIDTH (FIFO_COUNT_W)
    ) u_fifo (
        .sleep         (1'b0),
        .rst           (~rst_n),
        .wr_clk        (wr_clk),
        .wr_en         (wr_hsync && !wr_vsync && !fifo_full),
        .din           (wr_pixel),
        .full          (fifo_full),
        .overflow      (),
        .wr_rst_busy   (),
        .wr_ack        (),
        .wr_data_count (),
        .almost_full   (),
        .prog_full     (),
        .rd_clk        (rd_clk),
        .rd_en         (rd_en && !rd_empty),
        .dout          (rd_pixel),
        .empty         (rd_empty),
        .underflow     (),
        .rd_rst_busy   (),
        .data_valid    (),
        .rd_data_count (rd_count_i),
        .almost_empty  (),
        .prog_empty    (),
        .injectsbiterr (1'b0),
        .injectdbiterr (1'b0),
        .sbiterr       (),
        .dbiterr       ()
    );
endmodule

module EO1920x1080_To_HD1080p_LineBuffered(
    input  wire        rst_n,
    input  wire        wr_clk,
    input  wire        wr_hsync,
    input  wire        wr_vsync,
    input  wire [19:0] wr_pixel,
    input  wire        rd_clk,
    output wire        hd_de,
    output wire        hd_hsync,
    output wire        hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W       = 1920;
    localparam integer HD_ACTIVE_W = 1920;
    localparam integer HD_ACTIVE_H = 1080;
    localparam integer HD_TOTAL_W  = 2200;
    localparam integer HD_TOTAL_H  = 1125;
    localparam integer SAV_WORDS   = 4;
    localparam integer EAV_WORDS   = 4;
    localparam integer PREFILL     = SRC_W * 2;
    localparam [19:0]  BT1120_BLACK = {10'd64, 10'd512};

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        started;
    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    wire [19:0] fifo_pixel;
    wire        fifo_empty;
    wire [19:0] fifo_level;
    wire        fifo_rd_en;

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
    wire [11:0] cur_x = h_cnt - SAV_WORDS;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire        frame_origin = cur_active && (v_cnt == 11'd0) && (cur_x == 12'd0);
    wire        stream_ready = started || (frame_origin && (fifo_level >= PREFILL));

    assign fifo_rd_en = cur_active && stream_ready && !fifo_empty;

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (v_bit ^ h_bit), (f_bit ^ h_bit),
                         (f_bit ^ v_bit), (f_bit ^ v_bit ^ h_bit)};
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

    EO1920x1080_LineFifo u_fifo (
        .rst_n   (rst_n),
        .wr_clk  (wr_clk),
        .wr_hsync(wr_hsync),
        .wr_vsync(wr_vsync),
        .wr_pixel(wr_pixel),
        .rd_clk  (rd_clk),
        .rd_en   (fifo_rd_en),
        .rd_pixel(fifo_pixel),
        .rd_empty(fifo_empty),
        .rd_level(fifo_level)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt      <= 12'd0;
            v_cnt      <= 11'd0;
            started    <= 1'b0;
            hd_de_r    <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r  <= BT1120_BLACK;
        end else begin
            if (!started && frame_origin && (fifo_level >= PREFILL))
                started <= 1'b1;
            else if (started && cur_active && fifo_empty)
                started <= 1'b0;

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav)
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            else if (cur_eav)
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            else if (cur_active)
                hd_dout_r <= (stream_ready && !fifo_empty) ? fifo_pixel : BT1120_BLACK;
            else
                hd_dout_r <= BT1120_BLACK;

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module IR540x480_To_HD1080p_LineBuffered(
    input  wire       rst_n,
    input  wire       wr_clk,
    input  wire       wr_hsync,
    input  wire       wr_vsync,
    input  wire [7:0] wr_pixel,
    input  wire       rd_clk,
    output wire       hd_de,
    output wire       hd_hsync,
    output wire       hd_vsync,
    output wire [19:0] hd_dout
);
    localparam integer SRC_W       = 540;
    localparam integer SRC_H       = 480;
    localparam integer HD_ACTIVE_W = 1920;
    localparam integer HD_ACTIVE_H = 1080;
    localparam integer HD_TOTAL_W  = 2200;
    localparam integer HD_TOTAL_H  = 1125;
    localparam integer SAV_WORDS   = 4;
    localparam integer EAV_WORDS   = 4;
    localparam integer X_OFF       = (HD_ACTIVE_W - SRC_W) / 2;
    localparam integer Y_OFF       = (HD_ACTIVE_H - SRC_H) / 2;
    localparam integer PREFILL     = SRC_W * 32;
    localparam [19:0]  BT1120_BLACK = {10'd64, 10'd512};

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        started;
    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;

    wire [7:0] fifo_pixel;
    wire       fifo_empty;
    wire [18:0] fifo_level;
    wire       fifo_rd_en;

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
    wire [11:0] cur_x = h_cnt - SAV_WORDS;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire inside_img = cur_active &&
                      (cur_x >= X_OFF) && (cur_x < (X_OFF + SRC_W)) &&
                      (v_cnt >= Y_OFF) && (v_cnt < (Y_OFF + SRC_H));
    wire image_origin = cur_active && (cur_x == X_OFF) && (v_cnt == Y_OFF);
    wire stream_ready = started || (image_origin && (fifo_level >= PREFILL));

    assign fifo_rd_en = inside_img && stream_ready && !fifo_empty;

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (v_bit ^ h_bit), (f_bit ^ h_bit),
                         (f_bit ^ v_bit), (f_bit ^ v_bit ^ h_bit)};
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

    IR540x480_LineFifo #(.FIFO_WRITE_DEPTH(65536), .FIFO_COUNT_W(17)) u_fifo (
        .rst_n   (rst_n),
        .wr_clk  (wr_clk),
        .wr_hsync(wr_hsync),
        .wr_vsync(wr_vsync),
        .wr_pixel(wr_pixel),
        .rd_clk  (rd_clk),
        .rd_en   (fifo_rd_en),
        .rd_pixel(fifo_pixel),
        .rd_empty(fifo_empty),
        .rd_level(fifo_level)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt      <= 12'd0;
            v_cnt      <= 11'd0;
            started    <= 1'b0;
            hd_de_r    <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r  <= BT1120_BLACK;
        end else begin
            if (!started && image_origin && (fifo_level >= PREFILL))
                started <= 1'b1;
            else if (started && inside_img && fifo_empty)
                started <= 1'b0;

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav)
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            else if (cur_eav)
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            else if (cur_active)
                hd_dout_r <= (inside_img && stream_ready && !fifo_empty) ? {{fifo_pixel, 2'b00}, 10'd512} : BT1120_BLACK;
            else
                hd_dout_r <= BT1120_BLACK;

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module EO6Stack_To_HD1080p_LineBuffered(
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
    localparam integer SRC_W       = 640;
    localparam integer SRC_H       = 480;
    localparam integer HD_ACTIVE_W = 1920;
    localparam integer HD_ACTIVE_H = 1080;
    localparam integer HD_TOTAL_W  = 2200;
    localparam integer HD_TOTAL_H  = 1125;
    localparam integer SAV_WORDS   = 4;
    localparam integer EAV_WORDS   = 4;
    localparam integer STACK_H     = 960;
    localparam integer TOP_PREFILL = SRC_W * 320;
    localparam integer BOT_PREFILL = SRC_W * SRC_H;
    localparam [19:0]  BT1120_BLACK = {10'd64, 10'd512};

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;
    reg        cam0_started, cam1_started, cam2_started;
    reg        cam3_started, cam4_started, cam5_started;

    wire [19:0] cam0_pixel, cam1_pixel, cam2_pixel;
    wire [19:0] cam3_pixel, cam4_pixel, cam5_pixel;
    wire cam0_empty, cam1_empty, cam2_empty, cam3_empty, cam4_empty, cam5_empty;
    wire [19:0] cam0_level, cam1_level, cam2_level;
    wire [19:0] cam3_level, cam4_level, cam5_level;
    wire cam0_rd_en, cam1_rd_en, cam2_rd_en;
    wire cam3_rd_en, cam4_rd_en, cam5_rd_en;

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
    wire [11:0] cur_x = h_cnt - SAV_WORDS;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire        inside_stack = cur_active && (v_cnt < STACK_H);
    wire [2:0]  cur_cam_idx =
        (v_cnt < SRC_H) ?
            ((cur_x < SRC_W) ? 3'd0 : ((cur_x < (2*SRC_W)) ? 3'd1 : 3'd2)) :
            ((cur_x < SRC_W) ? 3'd3 : ((cur_x < (2*SRC_W)) ? 3'd4 : 3'd5));
    wire cam0_origin = cur_active && (v_cnt == 11'd0) && (cur_x == 12'd0);
    wire cam1_origin = cur_active && (v_cnt == 11'd0) && (cur_x == SRC_W);
    wire cam2_origin = cur_active && (v_cnt == 11'd0) && (cur_x == (2*SRC_W));
    wire cam3_origin = cur_active && (v_cnt == SRC_H) && (cur_x == 12'd0);
    wire cam4_origin = cur_active && (v_cnt == SRC_H) && (cur_x == SRC_W);
    wire cam5_origin = cur_active && (v_cnt == SRC_H) && (cur_x == (2*SRC_W));
    wire cam0_tile = inside_stack && (cur_cam_idx == 3'd0);
    wire cam1_tile = inside_stack && (cur_cam_idx == 3'd1);
    wire cam2_tile = inside_stack && (cur_cam_idx == 3'd2);
    wire cam3_tile = inside_stack && (cur_cam_idx == 3'd3);
    wire cam4_tile = inside_stack && (cur_cam_idx == 3'd4);
    wire cam5_tile = inside_stack && (cur_cam_idx == 3'd5);
    wire cam0_can_start = cam0_origin && (cam0_level >= TOP_PREFILL);
    wire cam1_can_start = cam1_origin && (cam1_level >= TOP_PREFILL);
    wire cam2_can_start = cam2_origin && (cam2_level >= TOP_PREFILL);
    wire cam3_can_start = cam3_origin && (cam3_level >= BOT_PREFILL);
    wire cam4_can_start = cam4_origin && (cam4_level >= BOT_PREFILL);
    wire cam5_can_start = cam5_origin && (cam5_level >= BOT_PREFILL);
    wire [5:0]  cam_ready = {cam5_started || cam5_can_start,
                             cam4_started || cam4_can_start,
                             cam3_started || cam3_can_start,
                             cam2_started || cam2_can_start,
                             cam1_started || cam1_can_start,
                             cam0_started || cam0_can_start};

    wire selected_empty =
        (cur_cam_idx == 3'd0) ? cam0_empty :
        (cur_cam_idx == 3'd1) ? cam1_empty :
        (cur_cam_idx == 3'd2) ? cam2_empty :
        (cur_cam_idx == 3'd3) ? cam3_empty :
        (cur_cam_idx == 3'd4) ? cam4_empty : cam5_empty;

    wire [19:0] selected_pixel =
        (cur_cam_idx == 3'd0) ? cam0_pixel :
        (cur_cam_idx == 3'd1) ? cam1_pixel :
        (cur_cam_idx == 3'd2) ? cam2_pixel :
        (cur_cam_idx == 3'd3) ? cam3_pixel :
        (cur_cam_idx == 3'd4) ? cam4_pixel : cam5_pixel;

    wire selected_ready = cam_ready[cur_cam_idx] && !selected_empty;

    assign cam0_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd0);
    assign cam1_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd1);
    assign cam2_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd2);
    assign cam3_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd3);
    assign cam4_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd4);
    assign cam5_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd5);

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (v_bit ^ h_bit), (f_bit ^ h_bit),
                         (f_bit ^ v_bit), (f_bit ^ v_bit ^ h_bit)};
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

    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(262144), .FIFO_COUNT_W(17), .FIFO_MEMORY_TYPE_STR("block"), .USE_ASYNC_FIFO(0), .FIFO_RELATED_CLOCKS(1)) u_cam0_fifo (
        .rst_n(rst_n), .wr_clk(cam0_wr_clk), .wr_hsync(cam0_wr_hsync), .wr_vsync(cam0_wr_vsync), .wr_pixel(cam0_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam0_rd_en), .rd_pixel(cam0_pixel), .rd_empty(cam0_empty), .rd_level(cam0_level)
    );
    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(262144), .FIFO_COUNT_W(17), .FIFO_MEMORY_TYPE_STR("ultra"), .USE_URAM_FIFO(1)) u_cam1_fifo (
        .rst_n(rst_n), .wr_clk(cam1_wr_clk), .wr_hsync(cam1_wr_hsync), .wr_vsync(cam1_wr_vsync), .wr_pixel(cam1_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam1_rd_en), .rd_pixel(cam1_pixel), .rd_empty(cam1_empty), .rd_level(cam1_level)
    );
    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(262144), .FIFO_COUNT_W(17), .FIFO_MEMORY_TYPE_STR("ultra"), .USE_URAM_FIFO(1)) u_cam2_fifo (
        .rst_n(rst_n), .wr_clk(cam2_wr_clk), .wr_hsync(cam2_wr_hsync), .wr_vsync(cam2_wr_vsync), .wr_pixel(cam2_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam2_rd_en), .rd_pixel(cam2_pixel), .rd_empty(cam2_empty), .rd_level(cam2_level)
    );
    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(524288), .FIFO_COUNT_W(18), .FIFO_MEMORY_TYPE_STR("ultra"), .USE_URAM_FIFO(1)) u_cam3_fifo (
        .rst_n(rst_n), .wr_clk(cam3_wr_clk), .wr_hsync(cam3_wr_hsync), .wr_vsync(cam3_wr_vsync), .wr_pixel(cam3_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam3_rd_en), .rd_pixel(cam3_pixel), .rd_empty(cam3_empty), .rd_level(cam3_level)
    );
    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(524288), .FIFO_COUNT_W(18), .FIFO_MEMORY_TYPE_STR("ultra"), .USE_URAM_FIFO(1)) u_cam4_fifo (
        .rst_n(rst_n), .wr_clk(cam4_wr_clk), .wr_hsync(cam4_wr_hsync), .wr_vsync(cam4_wr_vsync), .wr_pixel(cam4_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam4_rd_en), .rd_pixel(cam4_pixel), .rd_empty(cam4_empty), .rd_level(cam4_level)
    );
    EO1920x1080_Decimate_LineFifo #(.FIFO_WRITE_DEPTH(524288), .FIFO_COUNT_W(18), .FIFO_MEMORY_TYPE_STR("ultra"), .USE_URAM_FIFO(1)) u_cam5_fifo (
        .rst_n(rst_n), .wr_clk(cam5_wr_clk), .wr_hsync(cam5_wr_hsync), .wr_vsync(cam5_wr_vsync), .wr_pixel(cam5_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam5_rd_en), .rd_pixel(cam5_pixel), .rd_empty(cam5_empty), .rd_level(cam5_level)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt      <= 12'd0;
            v_cnt      <= 11'd0;
            cam0_started <= 1'b0;
            cam1_started <= 1'b0;
            cam2_started <= 1'b0;
            cam3_started <= 1'b0;
            cam4_started <= 1'b0;
            cam5_started <= 1'b0;
            hd_de_r    <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r  <= BT1120_BLACK;
        end else begin
            if (cam0_started && cam0_tile && cam0_empty)
                cam0_started <= 1'b0;
            else if (!cam0_started && cam0_can_start)
                cam0_started <= 1'b1;

            if (cam1_started && cam1_tile && cam1_empty)
                cam1_started <= 1'b0;
            else if (!cam1_started && cam1_can_start)
                cam1_started <= 1'b1;

            if (cam2_started && cam2_tile && cam2_empty)
                cam2_started <= 1'b0;
            else if (!cam2_started && cam2_can_start)
                cam2_started <= 1'b1;

            if (cam3_started && cam3_tile && cam3_empty)
                cam3_started <= 1'b0;
            else if (!cam3_started && cam3_can_start)
                cam3_started <= 1'b1;

            if (cam4_started && cam4_tile && cam4_empty)
                cam4_started <= 1'b0;
            else if (!cam4_started && cam4_can_start)
                cam4_started <= 1'b1;

            if (cam5_started && cam5_tile && cam5_empty)
                cam5_started <= 1'b0;
            else if (!cam5_started && cam5_can_start)
                cam5_started <= 1'b1;

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav)
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            else if (cur_eav)
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            else if (cur_active)
                hd_dout_r <= (inside_stack && selected_ready) ? selected_pixel : BT1120_BLACK;
            else
                hd_dout_r <= BT1120_BLACK;

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule

module IR6Stack_To_HD1080p_LineBuffered(
    input  wire        rst_n,
    input  wire        rd_clk,
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
    localparam integer SRC_W       = 540;
    localparam integer SRC_H       = 480;
    localparam integer HD_ACTIVE_W = 1920;
    localparam integer HD_ACTIVE_H = 1080;
    localparam integer HD_TOTAL_W  = 2200;
    localparam integer HD_TOTAL_H  = 1125;
    localparam integer SAV_WORDS   = 4;
    localparam integer EAV_WORDS   = 4;
    localparam integer STACK_W     = 3 * SRC_W;
    localparam integer STACK_H     = 2 * SRC_H;
    localparam integer TOP_PREFILL = SRC_W * 96;
    localparam integer BOT_PREFILL = SRC_W * SRC_H;
    localparam [19:0]  BT1120_BLACK = {10'd64, 10'd512};
    localparam [19:0]  ZERO_PAD_BLACK = {10'd0, 10'd512};

    reg [11:0] h_cnt;
    reg [10:0] v_cnt;
    reg        hd_de_r;
    reg        hd_hsync_r;
    reg        hd_vsync_r;
    reg [19:0] hd_dout_r;
    reg        cam0_started, cam1_started, cam2_started;
    reg        cam3_started, cam4_started, cam5_started;

    wire [7:0] cam0_pixel, cam1_pixel, cam2_pixel;
    wire [7:0] cam3_pixel, cam4_pixel, cam5_pixel;
    wire cam0_empty, cam1_empty, cam2_empty, cam3_empty, cam4_empty, cam5_empty;
    wire [18:0] cam0_level, cam1_level, cam2_level;
    wire [18:0] cam3_level, cam4_level, cam5_level;
    wire cam0_rd_en, cam1_rd_en, cam2_rd_en;
    wire cam3_rd_en, cam4_rd_en, cam5_rd_en;

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
    wire [11:0] cur_x = h_cnt - SAV_WORDS;
    wire [1:0]  cur_eav_idx = h_cnt - (SAV_WORDS + HD_ACTIVE_W);
    wire        inside_stack = cur_active && (cur_x < STACK_W) && (v_cnt < STACK_H);
    wire [2:0]  cur_cam_idx =
        (v_cnt < SRC_H) ?
            ((cur_x < SRC_W) ? 3'd0 : ((cur_x < (2*SRC_W)) ? 3'd1 : 3'd2)) :
            ((cur_x < SRC_W) ? 3'd3 : ((cur_x < (2*SRC_W)) ? 3'd4 : 3'd5));
    wire cam0_origin = cur_active && (v_cnt == 11'd0) && (cur_x == 12'd0);
    wire cam1_origin = cur_active && (v_cnt == 11'd0) && (cur_x == SRC_W);
    wire cam2_origin = cur_active && (v_cnt == 11'd0) && (cur_x == (2*SRC_W));
    wire cam3_origin = cur_active && (v_cnt == SRC_H) && (cur_x == 12'd0);
    wire cam4_origin = cur_active && (v_cnt == SRC_H) && (cur_x == SRC_W);
    wire cam5_origin = cur_active && (v_cnt == SRC_H) && (cur_x == (2*SRC_W));
    wire cam0_tile = inside_stack && (cur_cam_idx == 3'd0);
    wire cam1_tile = inside_stack && (cur_cam_idx == 3'd1);
    wire cam2_tile = inside_stack && (cur_cam_idx == 3'd2);
    wire cam3_tile = inside_stack && (cur_cam_idx == 3'd3);
    wire cam4_tile = inside_stack && (cur_cam_idx == 3'd4);
    wire cam5_tile = inside_stack && (cur_cam_idx == 3'd5);
    wire cam0_can_start = cam0_origin && (cam0_level >= TOP_PREFILL);
    wire cam1_can_start = cam1_origin && (cam1_level >= TOP_PREFILL);
    wire cam2_can_start = cam2_origin && (cam2_level >= TOP_PREFILL);
    wire cam3_can_start = cam3_origin && (cam3_level >= BOT_PREFILL);
    wire cam4_can_start = cam4_origin && (cam4_level >= BOT_PREFILL);
    wire cam5_can_start = cam5_origin && (cam5_level >= BOT_PREFILL);
    wire [5:0]  cam_ready = {cam5_started || cam5_can_start,
                             cam4_started || cam4_can_start,
                             cam3_started || cam3_can_start,
                             cam2_started || cam2_can_start,
                             cam1_started || cam1_can_start,
                             cam0_started || cam0_can_start};

    wire selected_empty =
        (cur_cam_idx == 3'd0) ? cam0_empty :
        (cur_cam_idx == 3'd1) ? cam1_empty :
        (cur_cam_idx == 3'd2) ? cam2_empty :
        (cur_cam_idx == 3'd3) ? cam3_empty :
        (cur_cam_idx == 3'd4) ? cam4_empty : cam5_empty;

    wire [7:0] selected_pixel =
        (cur_cam_idx == 3'd0) ? cam0_pixel :
        (cur_cam_idx == 3'd1) ? cam1_pixel :
        (cur_cam_idx == 3'd2) ? cam2_pixel :
        (cur_cam_idx == 3'd3) ? cam3_pixel :
        (cur_cam_idx == 3'd4) ? cam4_pixel : cam5_pixel;

    wire selected_ready = cam_ready[cur_cam_idx] && !selected_empty;

    assign cam0_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd0);
    assign cam1_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd1);
    assign cam2_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd2);
    assign cam3_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd3);
    assign cam4_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd4);
    assign cam5_rd_en = inside_stack && selected_ready && (cur_cam_idx == 3'd5);

    function [7:0] bt1120_xy;
        input f_bit;
        input v_bit;
        input h_bit;
        begin
            bt1120_xy = {1'b1, f_bit, v_bit, h_bit,
                         (v_bit ^ h_bit), (f_bit ^ h_bit),
                         (f_bit ^ v_bit), (f_bit ^ v_bit ^ h_bit)};
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

    IR540x480_LineFifo #(.FIFO_WRITE_DEPTH(65536), .FIFO_COUNT_W(17)) u_cam0_fifo (
        .rst_n(rst_n), .wr_clk(cam0_wr_clk), .wr_hsync(cam0_wr_hsync), .wr_vsync(cam0_wr_vsync), .wr_pixel(cam0_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam0_rd_en), .rd_pixel(cam0_pixel), .rd_empty(cam0_empty), .rd_level(cam0_level)
    );
    IR540x480_LineFifo #(.FIFO_WRITE_DEPTH(65536), .FIFO_COUNT_W(17)) u_cam1_fifo (
        .rst_n(rst_n), .wr_clk(cam1_wr_clk), .wr_hsync(cam1_wr_hsync), .wr_vsync(cam1_wr_vsync), .wr_pixel(cam1_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam1_rd_en), .rd_pixel(cam1_pixel), .rd_empty(cam1_empty), .rd_level(cam1_level)
    );
    IR540x480_LineFifo #(.FIFO_WRITE_DEPTH(65536), .FIFO_COUNT_W(17)) u_cam2_fifo (
        .rst_n(rst_n), .wr_clk(cam2_wr_clk), .wr_hsync(cam2_wr_hsync), .wr_vsync(cam2_wr_vsync), .wr_pixel(cam2_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam2_rd_en), .rd_pixel(cam2_pixel), .rd_empty(cam2_empty), .rd_level(cam2_level)
    );
    IR540x480_LineFifo u_cam3_fifo (
        .rst_n(rst_n), .wr_clk(cam3_wr_clk), .wr_hsync(cam3_wr_hsync), .wr_vsync(cam3_wr_vsync), .wr_pixel(cam3_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam3_rd_en), .rd_pixel(cam3_pixel), .rd_empty(cam3_empty), .rd_level(cam3_level)
    );
    IR540x480_LineFifo u_cam4_fifo (
        .rst_n(rst_n), .wr_clk(cam4_wr_clk), .wr_hsync(cam4_wr_hsync), .wr_vsync(cam4_wr_vsync), .wr_pixel(cam4_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam4_rd_en), .rd_pixel(cam4_pixel), .rd_empty(cam4_empty), .rd_level(cam4_level)
    );
    IR540x480_LineFifo u_cam5_fifo (
        .rst_n(rst_n), .wr_clk(cam5_wr_clk), .wr_hsync(cam5_wr_hsync), .wr_vsync(cam5_wr_vsync), .wr_pixel(cam5_wr_pixel),
        .rd_clk(rd_clk), .rd_en(cam5_rd_en), .rd_pixel(cam5_pixel), .rd_empty(cam5_empty), .rd_level(cam5_level)
    );

    always @(posedge rd_clk) begin
        if (!rst_n) begin
            h_cnt      <= 12'd0;
            v_cnt      <= 11'd0;
            cam0_started <= 1'b0;
            cam1_started <= 1'b0;
            cam2_started <= 1'b0;
            cam3_started <= 1'b0;
            cam4_started <= 1'b0;
            cam5_started <= 1'b0;
            hd_de_r    <= 1'b0;
            hd_hsync_r <= 1'b0;
            hd_vsync_r <= 1'b0;
            hd_dout_r  <= BT1120_BLACK;
        end else begin
            if (cam0_started && cam0_tile && cam0_empty)
                cam0_started <= 1'b0;
            else if (!cam0_started && cam0_can_start)
                cam0_started <= 1'b1;

            if (cam1_started && cam1_tile && cam1_empty)
                cam1_started <= 1'b0;
            else if (!cam1_started && cam1_can_start)
                cam1_started <= 1'b1;

            if (cam2_started && cam2_tile && cam2_empty)
                cam2_started <= 1'b0;
            else if (!cam2_started && cam2_can_start)
                cam2_started <= 1'b1;

            if (cam3_started && cam3_tile && cam3_empty)
                cam3_started <= 1'b0;
            else if (!cam3_started && cam3_can_start)
                cam3_started <= 1'b1;

            if (cam4_started && cam4_tile && cam4_empty)
                cam4_started <= 1'b0;
            else if (!cam4_started && cam4_can_start)
                cam4_started <= 1'b1;

            if (cam5_started && cam5_tile && cam5_empty)
                cam5_started <= 1'b0;
            else if (!cam5_started && cam5_can_start)
                cam5_started <= 1'b1;

            hd_de_r    <= cur_active;
            hd_hsync_r <= cur_active;
            hd_vsync_r <= ~cur_vblank;

            if (cur_sav)
                hd_dout_r <= bt1120_trs_word(h_cnt[1:0], 1'b0, cur_vblank, 1'b0);
            else if (cur_eav)
                hd_dout_r <= bt1120_trs_word(cur_eav_idx, 1'b0, cur_vblank, 1'b1);
            else if (cur_active)
                hd_dout_r <= inside_stack ? (selected_ready ? {{selected_pixel, 2'b00}, 10'd512} : ZERO_PAD_BLACK) : BT1120_BLACK;
            else
                hd_dout_r <= BT1120_BLACK;

            h_cnt <= h_next;
            v_cnt <= v_next;
        end
    end
endmodule
