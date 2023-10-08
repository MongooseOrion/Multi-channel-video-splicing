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
    parameter                     MEM_DQ_WIDTH         = 32    
)(
    input               rst                         ,
    input       [3:0]   command_in                  ,
    
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

    // 取数据 RAM
    input                           vesa_out_clk    ,
    input                           rd_fsync        ,
    input                           rd_en           ,
    output                          vesa_out_de     ,
    output [15:0]                   vesa_out_data   ,
    
    // AXI 总线
    output [CTRL_ADDR_WIDTH-1:0]  axi_awaddr        ,
    output [3:0]                  axi_awid          ,
    output [3:0]                  axi_awlen         ,
    output [2:0]                  axi_awsize        ,
    output [1:0]                  axi_awburst       ,
    input                         axi_awready       ,
    output                        axi_awvalid       ,

    output [MEM_DQ_WIDTH*8-1:0]   axi_wdata         ,
    output [MEM_DQ_WIDTH -1 :0]   axi_wstrb         ,
    input                         axi_wlast         ,
    output                        axi_wvalid        ,
    input                         axi_wready        ,
    input  [3 : 0]                axi_bid           ,                                      

    output [CTRL_ADDR_WIDTH-1:0]  axi_araddr        ,
    output [3:0]                  axi_arid          ,
    output [3:0]                  axi_arlen         ,
    output [2:0]                  axi_arsize        ,
    output [1:0]                  axi_arburst       ,
    output                        axi_arvalid       ,
    input                         axi_arready       ,

    output                        axi_rready        ,
    input  [MEM_DQ_WIDTH*8-1:0]   axi_rdata         ,
    input                         axi_rvalid        ,
    input                         axi_rlast         ,
    input  [3:0]                  axi_rid            
);

// 聚焦视图切换代码
parameter   CAM_1 = 4'b0001,
            CAM_2 = 4'b0010,
            CAM_FUSION = 4'b0011,
            HDMI = 4'b0100;

reg         ultimate_clk_in;
reg         ultimate_de_in;
reg         ultimate_vs_in;
reg [15:0]  ultimate_data_in;


// 相机 1 1/16
video_sampling_1 #(
    .IMAGE_TAG          (4'd1)
)video_sampling_cmos1 (
    .clk                (cmos1_pclk),
    .rst                (rst),
    .de_in              (cmos1_href),
    .vs_in              (cmos1_vsync),
    .rgb565_in          (cmos1_pix_data),
    .rd_addr            (),
    .rd_clk             (),
    .rd_valid           (),
    .data_out_ready     (),
    .rd_data            (),
    .trans_id           ()
);


// 相机 2 1/16
video_sampling_1 #(
    .IMAGE_TAG          (4'd2)
)video_sampling_cmos2 (
    .clk                (cmos2_pclk),
    .rst                (rst),
    .de_in              (cmos2_href),
    .vs_in              (cmos2_vsync),
    .rgb565_in          (cmos2_pix_data),
    .rd_addr            (),
    .rd_clk             (),
    .rd_valid           (),
    .data_out_ready     (),
    .rd_data            (),
    .trans_id           ()
);


// 相机融合 1/16
video_sampling_1 #(
    .IMAGE_TAG          (4'd3)
)video_sampling_cmos_fusion (
    .clk                (cmos_fusion_pclk),
    .rst                (rst),
    .de_in              (cmos_fusion_href),
    .vs_in              (cmos_fusion_vsync),
    .rgb565_in          (cmos_fusion_data),
    .rd_addr            (),
    .rd_clk             (),
    .rd_valid           (),
    .data_out_ready     (),
    .rd_data            (),
    .trans_id           ()
);


// HDMI 1/16
video_sampling_1 #(
    .IMAGE_TAG          (4'd4)
)video_sampling_hdmi (
    .clk                (hdmi_pclk),
    .rst                (rst),
    .de_in              (hdmi_href),
    .vs_in              (hdmi_vsync),
    .rgb565_in          (hdmi_pix_data),
    .rd_addr            (),
    .rd_clk             (),
    .rd_valid           (),
    .data_out_ready     (),
    .rd_data            (),
    .trans_id           ()
);


// 聚焦视图 9/16
// 960*560
always @(*) begin
    case(command_in)
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

video_sampling_2 #(
    .IMAGE_TAG          (4'd5)
)video_sampling_ultimate (
    .clk_in             (ultimate_clk_in),
    .rst                (rst),
    .vs_in              (ultimate_vs_in),
    .de_in              (ultimate_de_in),
    .data_in            (ultimate_data_in),
    .rd_clk             (),
    .rd_addr            (),
    .rd_valid           (),
    .data_out_ready     (),
    .rd_data            (),
    .trans_id           ()
);


// 上述内容循环仲裁从 AXI 写入 DDR
axi_arbitrate_wr u_axi_arbitrate_wr();

endmodule