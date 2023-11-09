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
// 将 ddr 的数据读出，可使用 outstanding 机制
// 
module axi_interconnect_rd #(
    parameter MEM_ROW_WIDTH        = 15     ,
    parameter MEM_COLUMN_WIDTH     = 10     ,
    parameter MEM_BANK_WIDTH       = 3      ,
    parameter CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter DQ_WIDTH          = 12'd32    ,
    parameter H_HEIGHT = 'd720              ,
    parameter H_WIDTH = 'd1280              ,
    parameter BURST_LEN = 'd10
)(
    input                               clk             ,
    input                               rst             ,

    // hdmi 时序相关信号
    input                               hdmi_vsync      ,
    input                               hdmi_href       ,

    // 输出数据给 buffer
    input                               init_done       ,
    input                               axi_wr_buf_wait ,   // 必须提前拉高并持续一段时间
    input  [1:0]                        channel_sel     ,
    output                              buf_wr_en       /*synthesis PAP_MARK_DEBUG="1"*/,
    output [DQ_WIDTH*8-1:0]             buf_wr_data     /*synthesis PAP_MARK_DEBUG="1"*/,    
    
    // AXI READ INTERFACE
    output                              axi_arvalid     /*synthesis PAP_MARK_DEBUG="1"*/,  
    input                               axi_arready     /*synthesis PAP_MARK_DEBUG="1"*/, 
    output [CTRL_ADDR_WIDTH-1:0]        axi_araddr      ,  
    output [3:0]                        axi_arid        ,  
    output [3:0]                        axi_arlen       ,  
    output [2:0]                        axi_arsize      ,  
    output [1:0]                        axi_arburst     ,  
                                                         
    output                              axi_rready      /*synthesis PAP_MARK_DEBUG="1"*/,  
    input  [DQ_WIDTH*8-1:0]             axi_rdata       ,  
    input                               axi_rvalid      /*synthesis PAP_MARK_DEBUG="1"*/,  
    input                               axi_rlast       /*synthesis PAP_MARK_DEBUG="1"*/,  
    input  [3:0]                        axi_rid         
);

parameter WIDTH_QD = H_WIDTH / 4;
parameter HEIGHT_QD = H_HEIGHT / 4;
parameter WIDTH_TC = H_WIDTH * 3/4;
parameter HEIGHT_TC = H_HEIGHT * 3/4;
parameter   INIT_WAIT = 4'b0000,              // AXI 读状态机
            WR1_WAIT = 4'b0001,
            WR_1 = 4'b0010,
            WR2_WAIT = 4'b0011,
            WR_2 = 4'b0100,
            WR3_WAIT = 4'b0101,
            WR_3 = 4'b0110,
            WR4_WAIT = 4'b0111,
            WR_4 = 4'b1000,
            WR5_WAIT = 4'b1001,
            WR_5 = 4'b1010;
// 地址偏移量
parameter FRAME_ADDR_OFFSET_1 = 'd30_000;
parameter FRAME_ADDR_OFFSET_2 = 'd260_000;
parameter   ADDR_OFFSET_1 = 'd0,                    
            ADDR_OFFSET_2 = FRAME_ADDR_OFFSET_1 * 2,  
            ADDR_OFFSET_3 = ADDR_OFFSET_2 + 2 * (FRAME_ADDR_OFFSET_1),      // 
            ADDR_OFFSET_4 = ADDR_OFFSET_3 + 2 * (FRAME_ADDR_OFFSET_1),
            ADDR_OFFSET_5 = ADDR_OFFSET_4 + 2 * (FRAME_ADDR_OFFSET_1);
parameter ADDR_STEP = BURST_LEN * 8;       // 首地址自增步长，1 个地址 32 位数据，这与芯片的 DQ 宽度有关




endmodule