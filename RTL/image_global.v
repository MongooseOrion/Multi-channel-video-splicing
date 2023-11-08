/* =======================================================================
* Copyright (c) 2023, MongooseOrion.
* All rights reserved.
*
* The following code snippet may contain portions that are derived from
* OPEN-SOURCE communities, and these portions will be licensed with: 
*
* <NULL>
*
* If there is no OPEN-SOURCE licenses are listed, it indicates none of
* content in this Code document is sourced from OPEN-SOURCE communities. 
*
* In this case, the document is protected by copyright, and any use of
* all or part of its content by individuals, organizations, or companies
* without authorization is prohibited, unless the project repository
* associated with this document has added relevant OPEN-SOURCE licenses
* by github.com/MongooseOrion. 
*
* Please make sure using the content of this document in accordance with 
* the respective OPEN-SOURCE licenses. 
* 
* THIS CODE IS PROVIDED BY https://github.com/MongooseOrion. 
* FILE ENCODER TYPE: GBK
* ========================================================================
*/
// 全画面缓存模块
// 
module image_global#(
    parameter                     MEM_ROW_WIDTH        = 15    ,
    parameter                     MEM_COLUMN_WIDTH     = 10    ,
    parameter                     MEM_BANK_WIDTH       = 3     ,
    parameter                     CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter                     MEM_DQ_WIDTH         = 32    ,
    parameter M_ADDR_WIDTH      = 5'd5             // buf 读通道位宽
)(
    input               ddr_clk                     ,
    input               rst                         ,
    input       [3:0]   ctrl_command_in             ,
    input       [3:0]   value_command_in            ,
    
    // 视频流输入
    input               cmos1_pclk                  ,
    input               cmos1_href                  ,
    input               cmos1_vsync                 ,
    input       [15:0]  cmos1_pix_data              ,
    input               cmos2_pclk                  ,
    input               cmos2_href                  ,
    input               cmos2_vsync                 ,
    input       [15:0]  cmos2_pix_data              ,
    input               cmos_fusion_pclk            ,
    input               cmos_fusion_href            ,
    input               cmos_fusion_vsync           ,
    input       [15:0]  cmos_fusion_data            ,
    input               hdmi_pclk                   ,
    input               hdmi_href                   ,
    input               hdmi_vsync                  ,
    input       [15:0]  hdmi_pix_data               ,

    // 取数据 RAM 所需的同步信号
    input                           vesa_out_clk    ,
    input                           vesa_out_vsync  ,
    input                           vesa_out_de     ,
    output [15:0]                   vesa_out_data   ,
    output                          de_out          ,
    
    // AXI 总线
    output [CTRL_ADDR_WIDTH-1:0]    axi_awaddr      ,
    output [3:0]                    axi_awid        ,
    output [3:0]                    axi_awlen       ,
    output [2:0]                    axi_awsize      ,
    output [1:0]                    axi_awburst     ,
    input                           axi_awready     ,
    output                          axi_awvalid     ,

    output [MEM_DQ_WIDTH*8-1:0]     axi_wdata       ,
    output [MEM_DQ_WIDTH -1 :0]     axi_wstrb       ,
    input                           axi_wlast       ,
    output                          axi_wvalid      ,
    input                           axi_wready      ,
    input  [3 : 0]                  axi_bid         ,                                      

    output [CTRL_ADDR_WIDTH-1:0]    axi_araddr      ,
    output [3:0]                    axi_arid        ,
    output [3:0]                    axi_arlen       ,
    output [2:0]                    axi_arsize      ,
    output [1:0]                    axi_arburst     ,
    output                          axi_arvalid     ,
    input                           axi_arready     ,

    output                          axi_rready      ,
    input  [MEM_DQ_WIDTH*8-1:0]     axi_rdata       ,
    input                           axi_rvalid      ,
    input                           axi_rlast       ,
    input  [3:0]                    axi_rid         ,

    output                          init_done
);

// 聚焦视图切换代码
parameter   CAM_1 = 4'b0001,
            CAM_2 = 4'b0010,
            CAM_FUSION = 4'b0011,
            HDMI = 4'b0100;

wire [M_ADDR_WIDTH-1'b1:0]      channel1_addr       ;
wire                            channel1_rvalid     /* synthesis syn_keep = 1 */;
wire                            channel1_rready     /* synthesis syn_keep = 1 */;
wire [MEM_DQ_WIDTH*8-1'b1:0]    channel1_data       ;
wire                            frame_end_flag_1    ;
wire [M_ADDR_WIDTH-1'b1:0]      channel2_addr       ;
wire                            channel2_rvalid     /* synthesis syn_keep = 1 */;
wire                            channel2_rready     /* synthesis syn_keep = 1 */;
wire [MEM_DQ_WIDTH*8-1'b1:0]    channel2_data       ;
wire                            frame_end_flag_2    ;
wire [M_ADDR_WIDTH-1'b1:0]      channel3_addr       ;
wire                            channel3_rvalid     ;
wire                            channel3_rready     ;
wire [MEM_DQ_WIDTH*8-1'b1:0]    channel3_data       ;
wire                            frame_end_flag_3    ;
wire [M_ADDR_WIDTH-1'b1:0]      channel4_addr       ;
wire                            channel4_rvalid     /* synthesis syn_keep = 1 */;
wire                            channel4_rready     /* synthesis syn_keep = 1 */;
wire [MEM_DQ_WIDTH*8-1'b1:0]    channel4_data       ;
wire                            frame_end_flag_4    ;
wire [M_ADDR_WIDTH-1'b1:0]      channel5_addr       ;
wire                            channel5_rvalid     ;
wire                            channel5_rready     ;
wire [MEM_DQ_WIDTH*8-1'b1:0]    channel5_data       ;
wire                            frame_end_flag_5    ;
wire                            axi_wr_buf_wait     ;
wire                            axi_rd_en           ;
wire [1:0]                      channel_sel         ;
wire                            buf_wr_en           ;
wire [MEM_DQ_WIDTH*8-1'b1:0]    buf_wr_data         ;

reg [3:0]   reg_value_command   ;
reg         ultimate_clk_in     ;
reg         ultimate_de_in      ;
reg         ultimate_vs_in      ;
reg [15:0]  ultimate_data_in    ;


// 相机 1 1/16
video_sampling #(
    .IMAGE_TAG          (4'd1),
    .SEL_MODE           (2'd1)
)video_sampling_cmos1 (
    .clk                (cmos1_pclk),
    .rst                (1'b1),
    .de_in              (cmos1_href),
    .vs_in              (cmos1_vsync),
    .rgb565_in          (cmos1_pix_data),
    .rd_addr            (channel1_addr   ),
    .rd_clk             (ddr_clk    ),
    .rd_valid           (channel1_rvalid ),
    .data_out_ready     (channel1_rready ),
    .rd_data            (channel1_data   ),
    .frame_end_flag     (frame_end_flag_1),
    .trans_id           ()
);


// 相机 2 1/16
video_sampling #(
    .IMAGE_TAG          (4'd2),
    .SEL_MODE           (2'd1)
)video_sampling_cmos2 (
    .clk                (cmos2_pclk),
    .rst                (1'b1),
    .de_in              (cmos2_href),
    .vs_in              (cmos2_vsync),
    .rgb565_in          (cmos2_pix_data),
    .rd_addr            (channel2_addr   ),
    .rd_clk             (ddr_clk    ),
    .rd_valid           (channel2_rvalid ),
    .data_out_ready     (channel2_rready ),
    .rd_data            (channel2_data   ),
    .frame_end_flag     (frame_end_flag_2),
    .trans_id           ()
);


// 相机融合 1/16
video_sampling #(
    .IMAGE_TAG          (4'd3),
    .SEL_MODE           (2'd1)
)video_sampling_cmos_fusion (
    .clk                (cmos_fusion_pclk),
    .rst                (1'b1),
    .de_in              (cmos_fusion_href),
    .vs_in              (cmos_fusion_vsync),
    .rgb565_in          (cmos_fusion_data),
    .rd_addr            (channel3_addr   ),
    .rd_clk             (ddr_clk    ),
    .rd_valid           (channel3_rvalid ),
    .data_out_ready     (channel3_rready ),
    .rd_data            (channel3_data   ),
    .frame_end_flag     (frame_end_flag_3),
    .trans_id           ()
);


// HDMI 1/16
video_sampling #(
    .IMAGE_TAG          (4'd4),
    .SEL_MODE           (2'd1)
)video_sampling_hdmi (
    .clk                (hdmi_pclk),
    .rst                (1'b1),
    .de_in              (hdmi_href),
    .vs_in              (hdmi_vsync),
    .rgb565_in          (hdmi_pix_data),
    .rd_addr            (channel4_addr   ),
    .rd_clk             (ddr_clk    ),
    .rd_valid           (channel4_rvalid ),
    .data_out_ready     (channel4_rready ),
    .rd_data            (channel4_data   ),
    .frame_end_flag     (frame_end_flag_4),
    .trans_id           ()
);


// 聚焦视图 9/16
// 960*560
always @(*) begin
    if(ctrl_command_in == 4'b1111) begin
        if(value_command_in == 4'b0) begin
            reg_value_command <= reg_value_command;
        end
        else begin
            reg_value_command <= value_command_in;
        end
    end
    else begin
        reg_value_command <= 4'b0;
    end
end

always @(*) begin
    case(reg_value_command)
        CAM_1: begin
            ultimate_clk_in <= cmos1_pclk;
            ultimate_vs_in <= cmos1_vsync;
            ultimate_de_in <= cmos1_href;
            ultimate_data_in <= cmos1_pix_data;
        end
        CAM_2: begin
            ultimate_clk_in <= cmos2_pclk;
            ultimate_vs_in <= cmos2_vsync;
            ultimate_de_in <= cmos2_href;
            ultimate_data_in <= cmos2_pix_data;
        end
        CAM_FUSION: begin
            ultimate_clk_in <= cmos_fusion_pclk;
            ultimate_vs_in <= cmos_fusion_vsync;
            ultimate_de_in <= cmos_fusion_href;
            ultimate_data_in <= cmos_fusion_data;
        end
        HDMI: begin
            ultimate_clk_in <= hdmi_pclk;
            ultimate_vs_in <= hdmi_vsync;
            ultimate_de_in <= hdmi_href;
            ultimate_data_in <= hdmi_pix_data;
        end
        default: begin
            ultimate_clk_in <= cmos1_pclk;
            ultimate_vs_in <= cmos1_vsync;
            ultimate_de_in <= cmos1_href;
            ultimate_data_in <= cmos1_pix_data;
        end
    endcase
end

video_sampling #(
    .IMAGE_TAG          (4'd5),
    .SEL_MODE           (2'd2)
)video_sampling_ultimate (
    .clk                (ultimate_clk_in),
    .rst                (1'b1),
    .vs_in              (ultimate_vs_in),
    .de_in              (ultimate_de_in),
    .rgb565_in          (ultimate_data_in),
    .rd_clk             (ddr_clk     ),
    .rd_addr            (channel5_addr    ),
    .rd_valid           (channel5_rvalid  ),
    .data_out_ready     (channel5_rready  ),
    .rd_data            (channel5_data    ),
    .frame_end_flag     (frame_end_flag_5 ),
    .trans_id           ()
);


// 上述内容循环仲裁从 AXI 写入 DDR
axi_interconnect_wr u_axi_interconnect_wr(
    .clk                            (ddr_clk),
    .rst                            (rst),

    .channel1_addr                  (channel1_addr   ),
    .channel1_rvalid                (channel1_rvalid ),
    .channel1_rready                (channel1_rready ),
    .channel1_data                  (channel1_data   ),
    .frame_end_flag_1               (frame_end_flag_1),

    .channel2_addr                  (channel2_addr   ),
    .channel2_rvalid                (channel2_rvalid ),
    .channel2_rready                (channel2_rready ),
    .channel2_data                  (channel2_data   ),
    .frame_end_flag_2               (frame_end_flag_2),

    .channel3_addr                  (channel3_addr   ),
    .channel3_rvalid                (channel3_rvalid ),
    .channel3_rready                (channel3_rready ),
    .channel3_data                  (channel3_data   ),
    .frame_end_flag_3               (frame_end_flag_3),

    .channel4_addr                  (channel4_addr   ),
    .channel4_rvalid                (channel4_rvalid ),
    .channel4_rready                (channel4_rready ),
    .channel4_data                  (channel4_data   ),
    .frame_end_flag_4               (frame_end_flag_4),

    .channel5_addr                  (channel5_addr   ),
    .channel5_rvalid                (channel5_rvalid ),
    .channel5_rready                (channel5_rready ),
    .channel5_data                  (channel5_data   ),
    .frame_end_flag_5               (frame_end_flag_5),

    .init_done                      (init_done),

    .axi_awaddr                     (axi_awaddr  ),
    .axi_awid                       (axi_awid    ),
    .axi_awlen                      (axi_awlen   ),
    .axi_awsize                     (axi_awsize  ),
    .axi_awburst                    (axi_awburst ),
    .axi_awready                    (axi_awready ),
    .axi_awvalid                    (axi_awvalid ),
    .axi_wdata                      (axi_wdata   ),
    .axi_wstrb                      (axi_wstrb   ),
    .axi_wlast                      (axi_wlast   ),
    .axi_wvalid                     (axi_wvalid  ),
    .axi_wready                     (axi_wready  ),
    .axi_bid                        (axi_bid     ),
    .axi_bvalid                     (axi_bvalid  ),
    .axi_bready                     (axi_bready  )
);


// 从 DDR 读出给 buffer，以便 HDMI 显示
axi_interconnect_rd u_axi_interconnect_rd(
    .clk                        (ddr_clk),
    .rst                        (rst),
    .init_done                  (init_done),
    .axi_wr_buf_wait            ( ),
    .channel_sel                (channel_sel     ),
    .buf_wr_en                  (buf_wr_en       ),
    .buf_wr_data                (buf_wr_data     ),
    .hdmi_vsync                 (vesa_out_vsync  ),
    .hdmi_href                  (vesa_out_de     ),

    .axi_arvalid                (axi_arvalid ),
    .axi_arready                (axi_arready ),
    .axi_araddr                 (axi_araddr  ),
    .axi_arid                   (axi_arid    ),
    .axi_arlen                  (axi_arlen   ),
    .axi_arsize                 (axi_arsize  ),
    .axi_arburst                (axi_arburst ),        
    .axi_rready                 (axi_rready  ),
    .axi_rdata                  (axi_rdata   ),
    .axi_rvalid                 (axi_rvalid  ),
    .axi_rlast                  (axi_rlast   ),
    .axi_rid                    (axi_rid     )
); 


// 输出数据缓存 buf
ddr_rd_buf u_ddr_rd_buf(
    .clk                        (ddr_clk),
    .rst                        (rst),
    .buf_wr_en                  (buf_wr_en   ),
    .buf_wr_data                (buf_wr_data ),
    .channel_sel                (channel_sel ),
    .axi_wr_buf_wait            (),

    .hdmi_href                  (vesa_out_de),
    .hdmi_vsync                 (vesa_out_vsync),
    .rd_clk                     (vesa_out_clk),
    .rd_rst                     (rst),
    .de_o                       (de_out),
    .rgb565_out                 (vesa_out_data)
);

endmodule