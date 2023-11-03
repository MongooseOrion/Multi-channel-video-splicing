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
// 对各图像输入数据模块进行循环 AXI 输入，以将各图像保存到不同的 ddr 地址区域
//
module axi_interconnect_wr #(
    parameter MEM_ROW_WIDTH        = 15    ,
    parameter MEM_COLUMN_WIDTH     = 10    ,
    parameter MEM_BANK_WIDTH       = 3     ,
    parameter CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter M_ADDR_WIDTH      = 5'd5,             // buf 读通道位宽
    parameter S_ADDR_WIDTH      = 6'd40,
    parameter AXI_ADDR_WIDTH    = 6'd27,
    parameter DQ_WIDTH          = 12'd32,
    parameter BURST_LEN         = 12'd16,
    parameter PIX_WIDTH         = 12'd16,
    parameter LINE_ADDR_WIDTH   = 16'd19,
    parameter FRAME_CNT_WIDTH   = 16'd8
)(
    input                               clk,                // ddr core clk
    input                               rst,
    // 通道 1
    output                              channel1_clk    ,
    output reg  [M_ADDR_WIDTH-1'b1:0]   channel1_addr   ,
    output reg                          channel1_rvalid ,
    input                               channel1_rready ,
    input       [DQ_WIDTH*8-1'b1:0]     channel1_data   ,
    input                               frame_end_flag_1,
    // 通道 2
    output                              channel2_clk    ,
    output reg  [M_ADDR_WIDTH-1'b1:0]   channel2_addr   ,
    output reg                          channel2_rvalid ,
    input                               channel2_rready ,
    input       [DQ_WIDTH*8-1'b1:0]     channel2_data   ,
    input                               frame_end_flag_2,
    // 通道 3
    output                              channel3_clk    ,
    output reg  [M_ADDR_WIDTH-1'b1:0]   channel3_addr   ,
    output reg                          channel3_rvalid ,
    input                               channel3_rready ,
    input       [DQ_WIDTH*8-1'b1:0]     channel3_data   ,
    input                               frame_end_flag_3,
    // 通道 4
    output                              channel4_clk    ,
    output reg  [M_ADDR_WIDTH-1'b1:0]   channel4_addr   ,
    output reg                          channel4_rvalid ,
    input                               channel4_rready ,
    input       [DQ_WIDTH*8-1'b1:0]     channel4_data   ,
    input                               frame_end_flag_4,
    // 通道 5
    output                              channel5_clk    ,
    output reg  [M_ADDR_WIDTH-1'b1:0]   channel5_addr   ,
    output reg                          channel5_rvalid ,
    input                               channel5_rready ,
    input       [DQ_WIDTH*8-1'b1:0]     channel5_data   ,
    input                               frame_end_flag_5,

    output reg                          axi_rd_en       ,

    // AXI WRITE INTERFACE
    output [CTRL_ADDR_WIDTH-1:0]        axi_awaddr      ,
    output [3:0]                        axi_awid        ,
    output [3:0]                        axi_awlen       ,
    output [2:0]                        axi_awsize      ,
    output [1:0]                        axi_awburst     ,
    input                               axi_awready     ,
    output                              axi_awvalid     ,

    output [DQ_WIDTH*8-1'b1:0]          axi_wdata       ,
    output [DQ_WIDTH -1'b1 :0]          axi_wstrb       ,
    input                               axi_wlast       ,
    output                              axi_wvalid      ,
    input                               axi_wready      ,

    input  [3:0]                        axi_bid         ,
    input                               axi_bvalid      ,
    output                              axi_bready      
);

parameter   INIT_WAIT = 4'b0000,       // 定义读取状态
            CH_1 = 4'b0001,
            CH2_WAIT = 4'b0010,
            CH_2 = 4'b0011,
            CH3_WAIT = 4'b0100,
            CH_3 = 4'b0101,
            CH4_WAIT = 4'b0110,
            CH_4 = 4'b0111,
            CH5_WAIT = 4'b1000,
            CH_5 = 4'b1001;
// 地址偏移量
parameter FRAME_ADDR_OFFSET = 'd40960;
parameter   ADDR_OFFSET_1 = 'd0,                    // 0-40959, 40960-81919
            ADDR_OFFSET_2 = FRAME_ADDR_OFFSET * 2,  // 81920-122879, 122880-163839
            ADDR_OFFSET_3 = ADDR_OFFSET_2 + 2 * (FRAME_ADDR_OFFSET),      // 
            ADDR_OFFSET_4 = ADDR_OFFSET_3 + 2 * (FRAME_ADDR_OFFSET),
            ADDR_OFFSET_5 = ADDR_OFFSET_4 + 2 * (FRAME_ADDR_OFFSET);

wire                            pose_axi_wready ;

reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr  ;
reg                             reg_axi_awvalid ;
reg [DQ_WIDTH*8-1'b1:0]         reg_axi_wdata   ;
reg                             reg_axi_wvalid  ;
reg                             reg_axi_bready  ;
reg                             reg_axi_rready  ;

reg [3:0]                       buf_rd_state        ;
reg                             axi_wr_en           ;
reg                             axi_wready_temp     ;
reg [4:0]                       burst_len_count     ;
reg                             addr_head_flag      ;
reg [DQ_WIDTH*8-1'b1:0]         channel1_data_d1    ;
reg [DQ_WIDTH*8-1'b1:0]         channel2_data_d1    ;
reg [DQ_WIDTH*8-1'b1:0]         channel3_data_d1    ;
reg [DQ_WIDTH*8-1'b1:0]         channel4_data_d1    ;
reg [DQ_WIDTH*8-1'b1:0]         channel5_data_d1    ;
reg [1:0]                       frame_addr_count_1  ;
reg [1:0]                       frame_addr_count_2  ;
reg [1:0]                       frame_addr_count_3  ;
reg [1:0]                       frame_addr_count_4  ;
reg [1:0]                       frame_addr_count_5  ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr_1    ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr_2    ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr_3    ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr_4    ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_awaddr_5    ;

assign channel1_clk = clk   ;
assign channel2_clk = clk   ;
assign channel3_clk = clk   ;
assign channel4_clk = clk   ;
assign channel5_clk = clk   ;

assign axi_awaddr   = reg_axi_awaddr        ;
assign axi_awvalid  = reg_axi_awvalid       ;
assign axi_awlen    = BURST_LEN - 1'b1      ;   // 突发长度：16
assign axi_awsize   = DQ_WIDTH*8/8          ;   // DATA_LEN = 256
assign axi_awburst  = 2'b01                 ;
assign axi_wdata    = reg_axi_wdata         ;
assign axi_wvalid   = reg_axi_wvalid        ;
assign axi_wstrb    = {DQ_WIDTH{1'b1}}      ;
assign axi_bready   = reg_axi_bready        ;


// 取数据状态机跳转
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        buf_rd_state <= 'b0;
    end
    else begin
        case(buf_rd_state)
            INIT_WAIT: begin                // 握手 buf 传输协议，以及准备好 axi 写首地址
                if((channel1_rready == 1'b1) && (axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                    buf_rd_state <= CH_1;
                end
                else begin
                    buf_rd_state <= INIT_WAIT;
                end
            end
            CH_1: begin                     // 提取 buf 数据，并送入 axi 写通道
                //if((axi_bready == 1'b1) && (axi_bvalid == 1'b1)) begin
                if(axi_wlast) begin
                    buf_rd_state <= CH2_WAIT;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH2_WAIT: begin
                if((channel2_rready == 1'b1) && (axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                    buf_rd_state <= CH_2;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH_2: begin
                //if((axi_bready == 1'b1) && (axi_bvalid == 1'b1)) begin
                if(axi_wlast) begin
                    buf_rd_state <= CH3_WAIT;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH3_WAIT: begin
                if((channel3_rready == 1'b1) && (axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                    buf_rd_state <= CH_3;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH_3: begin
                //if((axi_bready == 1'b1) && (axi_bvalid == 1'b1)) begin
                if(axi_wlast) begin
                    buf_rd_state <= CH4_WAIT;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH4_WAIT: begin
                if((channel4_rready == 1'b1) && (axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                    buf_rd_state <= CH_4;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH_4: begin
                //if((axi_bready == 1'b1) && (axi_bvalid == 1'b1))begin
                if(axi_wlast) begin
                    buf_rd_state <= CH5_WAIT;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH5_WAIT: begin
                if((channel5_rready == 1'b1) && (axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                    buf_rd_state <= CH_5;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            CH_5: begin
                //if((axi_bready == 1'b1) && (axi_bvalid == 1'b1)) begin
                if(axi_wlast) begin
                    buf_rd_state <= INIT_WAIT;
                end
                else begin
                    buf_rd_state <= buf_rd_state;
                end
            end
            default: buf_rd_state <= INIT_WAIT;
        endcase
    end
end


// 状态机内部关于握手的信号
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        channel1_rvalid <= 'b0;
        channel2_rvalid <= 'b0;
        channel3_rvalid <= 'b0;
        channel4_rvalid <= 'b0;
        channel5_rvalid <= 'b0;
        reg_axi_awvalid <= 'b0;
        reg_axi_wvalid <= 'b0;
    end
    else begin
        case(buf_rd_state)
            INIT_WAIT: begin
                if(channel1_rready) begin               // buf 读握手
                    channel1_rvalid <= 1'b0;
                end
                else begin
                    channel1_rvalid <= 1'b1;
                end
                if((channel1_rready == 1'b1) && (channel1_rvalid == 1'b1)) begin    // axi 写地址握手
                    reg_axi_awvalid <= 1'b1;
                end
                else if((axi_awready == 1'b1) && (axi_awvalid == 1'b1)) begin
                    reg_axi_awvalid <= 1'b0;
                end
                else begin
                    reg_axi_awvalid <= reg_axi_awvalid;
                end
            end
            CH_1: begin
                if(axi_wlast) begin
                    reg_axi_wvalid <= 1'b0;
                end
                else begin
                    reg_axi_wvalid <= 1'b1;
                end
            end
            CH2_WAIT: begin
                if(channel2_rready) begin               // buf 读握手
                    channel2_rvalid <= 1'b0;
                end
                else begin
                    channel2_rvalid <= 1'b1;
                end
                if((channel2_rready == 1'b1) && (channel2_rvalid == 1'b1)) begin    // axi 写地址握手
                    reg_axi_awvalid <= 1'b1;
                end
                else if((axi_awready == 1'b1) && (axi_awvalid == 1'b1)) begin
                    reg_axi_awvalid <= 1'b0;
                end
                else begin
                    reg_axi_awvalid <= reg_axi_awvalid;
                end
            end
            CH_2: begin
                if(axi_wlast) begin
                    reg_axi_wvalid <= 1'b0;
                end
                else begin
                    reg_axi_wvalid <= 1'b1;
                end
            end
            CH3_WAIT: begin
                if(channel3_rready) begin               // buf 读握手
                    channel3_rvalid <= 1'b0;
                end
                else begin
                    channel3_rvalid <= 1'b1;
                end
                if((channel3_rready == 1'b1) && (channel3_rvalid == 1'b1)) begin    // axi 写地址握手
                    reg_axi_awvalid <= 1'b1;
                end
                else if((axi_awready == 1'b1) && (axi_awvalid == 1'b1)) begin
                    reg_axi_awvalid <= 1'b0;
                end
                else begin
                    reg_axi_awvalid <= reg_axi_awvalid;
                end
            end
            CH_3: begin
                if(axi_wlast) begin
                    reg_axi_wvalid <= 1'b0;
                end
                else begin
                    reg_axi_wvalid <= 1'b1;
                end
            end
            CH4_WAIT: begin
                if(channel4_rready) begin               // buf 读握手
                    channel4_rvalid <= 1'b0;
                end
                else begin
                    channel4_rvalid <= 1'b1;
                end
                if((channel4_rready == 1'b1) && (channel4_rvalid == 1'b1)) begin    // axi 写地址握手
                    reg_axi_awvalid <= 1'b1;
                end
                else if((axi_awready == 1'b1) && (axi_awvalid == 1'b1)) begin
                    reg_axi_awvalid <= 1'b0;
                end
                else begin
                    reg_axi_awvalid <= reg_axi_awvalid;
                end
            end
            CH_4: begin
                if(axi_wlast) begin
                    reg_axi_wvalid <= 1'b0;
                end
                else begin
                    reg_axi_wvalid <= 1'b1;
                end
            end
            CH5_WAIT: begin
                if(channel5_rready) begin               // buf 读握手
                    channel5_rvalid <= 1'b0;
                end
                else begin
                    channel5_rvalid <= 1'b1;
                end
                if((channel5_rready == 1'b1) && (channel5_rvalid == 1'b1)) begin    // axi 写地址握手
                    reg_axi_awvalid <= 1'b1;
                end
                else if((axi_awready == 1'b1) && (axi_awvalid == 1'b1)) begin
                    reg_axi_awvalid <= 1'b0;
                end
                else begin
                    reg_axi_awvalid <= reg_axi_awvalid;
                end
            end
            CH_5: begin
                if(axi_wlast) begin
                    reg_axi_wvalid <= 1'b0;
                end
                else begin
                    reg_axi_wvalid <= 1'b1;
                end
            end
            default: begin
                channel1_rvalid <= 1'b0;
                channel2_rvalid <= 1'b0;
                channel3_rvalid <= 1'b0;
                channel4_rvalid <= 1'b0;
                channel5_rvalid <= 1'b0;
                reg_axi_awvalid <= 1'b0;
                reg_axi_wvalid <= 1'b0;
            end
        endcase
    end
end


// 突发长度计数
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        burst_len_count <= 'b0;
    end
    else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1)) begin
        if(burst_len_count == BURST_LEN - 1'b1) begin
            burst_len_count <= 'b0;
        end
        else begin
            burst_len_count <= burst_len_count + 1'b1;
        end
    end
    else begin
        burst_len_count <= 5'b0;
    end
end


// 指示在读 buf 阶段先写入一个读地址，然后等待
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        addr_head_flag <= 'b0;
    end
    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
        addr_head_flag <= 1'b1;
    end
    else begin
        addr_head_flag <= 1'b0;
    end
end


// wready 上升沿检测
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        axi_wready_temp <= 'b0;
    end
    else begin
        axi_wready_temp <= axi_wready;
    end
end
assign pose_axi_wready = ((axi_wready) && (~axi_wready_temp)) ? 1'b1 : 1'b0;


// 向外（buffer）发出读地址请求，这必须在 AXI 总线的 wvalid 拉高后马上送
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        channel1_addr <= 'b0;
        channel2_addr <= 'b0;
        channel3_addr <= 'b0;
        channel4_addr <= 'b0;
        channel5_addr <= 'b0;
        frame_addr_count_1 <= 'b0;
        frame_addr_count_2 <= 'b0;
        frame_addr_count_3 <= 'b0;
        frame_addr_count_4 <= 'b0;
        frame_addr_count_5 <= 'b0;
        reg_axi_awaddr_1 <= 'b0;
        reg_axi_awaddr_2 <= 'b0;
        reg_axi_awaddr_3 <= 'b0;
        reg_axi_awaddr_4 <= 'b0;
        reg_axi_awaddr_5 <= 'b0;
        reg_axi_awaddr <= 'b0;
        channel1_data_d1 <= 'b0;
        channel2_data_d1 <= 'b0;
        channel3_data_d1 <= 'b0;
        channel4_data_d1 <= 'b0;
        channel5_data_d1 <= 'b0;
    end
    else begin
        case(buf_rd_state)
            INIT_WAIT: begin
                if(frame_addr_count_1 == 2'd0) begin
                    if((channel1_rvalid == 1'b1) && (channel1_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_1 + reg_axi_awaddr_1;         // 没握手之前生成首地址
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_1 <= reg_axi_awaddr_1 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_1 <= reg_axi_awaddr_1;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else if(frame_addr_count_1 == 2'd1) begin
                    if((channel1_rvalid == 1'b1) && (channel1_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_1 + FRAME_ADDR_OFFSET + reg_axi_awaddr_1;
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_1 <= reg_axi_awaddr_1 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_1 <= reg_axi_awaddr_1;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else begin
                    reg_axi_awaddr_1 <= 'b0;
                    reg_axi_awaddr <= 'b0;
                end
            end
            CH_1: begin
                if(addr_head_flag) begin
                    channel1_addr <= channel1_addr + 1'b1;
                    channel1_data_d1 <= channel1_data;
                end
                else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1) && (burst_len_count < BURST_LEN - 1'b1)) begin
                    channel1_addr <= channel1_addr + 1'b1;
                end
                else begin
                    channel1_addr <= channel1_addr;
                end
                if(frame_end_flag_1) begin 
                    reg_axi_awaddr_1 <= 'b0;                    // 指示帧结束信号来临时，用于累加的地址信号必须清零
                    if(frame_addr_count_1 == 2'd1) begin        // 每帧结束地址偏移计数信号
                        frame_addr_count_1 <= 2'b0;
                    end
                    else begin
                        frame_addr_count_1 <= frame_addr_count_1 + 1'b1;
                    end
                end
                else begin
                    reg_axi_awaddr_1 <= reg_axi_awaddr_1;
                    frame_addr_count_1 <= frame_addr_count_1;
                end
            end
            CH2_WAIT: begin
                if(frame_addr_count_2 == 2'd0) begin
                    if((channel2_rvalid == 1'b1) && (channel2_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_2 + reg_axi_awaddr_2;         // 没握手之前生成首地址
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_2 <= reg_axi_awaddr_2 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_2 <= reg_axi_awaddr_2;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else if(frame_addr_count_2 == 2'd1) begin
                    if((channel2_rvalid == 1'b1) && (channel2_rready == 1'b1)) begin
                        reg_axi_awaddr_2 <= reg_axi_awaddr_2 + BURST_LEN;
                        reg_axi_awaddr <= ADDR_OFFSET_2 + FRAME_ADDR_OFFSET + reg_axi_awaddr_2;
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_2 + FRAME_ADDR_OFFSET + reg_axi_awaddr_2;
                        reg_axi_awaddr_2 <= reg_axi_awaddr_2 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_2 <= reg_axi_awaddr_2;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else begin
                    reg_axi_awaddr_2 <= 'b0;
                    reg_axi_awaddr <= 'b0;
                end
            end
            CH_2: begin
                if(addr_head_flag) begin
                    channel2_addr <= channel2_addr + 1'b1;
                    channel2_data_d1 <= channel2_data;
                end
                else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1) && (burst_len_count < BURST_LEN - 1'b1)) begin
                    channel2_addr <= channel2_addr + 1'b1;
                end
                else begin
                    channel2_addr <= channel2_addr;
                end
                if(frame_end_flag_2) begin 
                    reg_axi_awaddr_2 <= 'b0;                    // 指示帧结束信号来临时，用于累加的地址信号必须清零
                    if(frame_addr_count_2 == 2'd1) begin        // 每帧结束地址偏移计数信号
                        frame_addr_count_2 <= 2'b0;
                    end
                    else begin
                        frame_addr_count_2 <= frame_addr_count_2 + 1'b1;
                    end
                end
                else begin
                    reg_axi_awaddr_2 <= reg_axi_awaddr_2;
                    frame_addr_count_2 <= frame_addr_count_2;
                end
            end
            CH3_WAIT: begin
                if(frame_addr_count_3 == 2'd0) begin
                    if((channel3_rvalid == 1'b1) && (channel3_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_3 + reg_axi_awaddr_3;         // 没握手之前生成首地址
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_3 <= reg_axi_awaddr_3 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_3 <= reg_axi_awaddr_3;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else if(frame_addr_count_3 == 2'd1) begin
                    if((channel3_rvalid == 1'b1) && (channel3_rready == 1'b1)) begin
                        reg_axi_awaddr_3 <= reg_axi_awaddr_3 + BURST_LEN;
                        reg_axi_awaddr <= ADDR_OFFSET_3 + FRAME_ADDR_OFFSET + reg_axi_awaddr_3;
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_3 + FRAME_ADDR_OFFSET + reg_axi_awaddr_3;
                        reg_axi_awaddr_3 <= reg_axi_awaddr_3 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_3 <= reg_axi_awaddr_3;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else begin
                    reg_axi_awaddr_3 <= 'b0;
                    reg_axi_awaddr <= 'b0;
                end
            end
            CH_3: begin
                if(addr_head_flag) begin
                    channel3_addr <= channel3_addr + 1'b1;
                    channel3_data_d1 <= channel3_data;
                end
                else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1) && (burst_len_count < BURST_LEN - 1'b1)) begin
                    channel3_addr <= channel3_addr + 1'b1;
                end
                else begin
                    channel3_addr <= channel3_addr;
                end
                if(frame_end_flag_3) begin 
                    reg_axi_awaddr_3 <= 'b0;                    // 指示帧结束信号来临时，用于累加的地址信号必须清零
                    if(frame_addr_count_3 == 2'd1) begin        // 每帧结束地址偏移计数信号
                        frame_addr_count_3 <= 2'b0;
                    end
                    else begin
                        frame_addr_count_3 <= frame_addr_count_3 + 1'b1;
                    end
                end
                else begin
                    reg_axi_awaddr_3 <= reg_axi_awaddr_3;
                    frame_addr_count_3 <= frame_addr_count_3;
                end
            end
            CH4_WAIT: begin
                if(frame_addr_count_4 == 2'd0) begin
                    if((channel4_rvalid == 1'b1) && (channel4_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_4 + reg_axi_awaddr_4;         // 没握手之前生成首地址
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_4 <= reg_axi_awaddr_4 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_4 <= reg_axi_awaddr_4;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else if(frame_addr_count_4 == 2'd1) begin
                    if((channel4_rvalid == 1'b1) && (channel4_rready == 1'b1)) begin
                        reg_axi_awaddr_4 <= reg_axi_awaddr_4 + BURST_LEN;
                        reg_axi_awaddr <= ADDR_OFFSET_4 + FRAME_ADDR_OFFSET + reg_axi_awaddr_4;
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_4 + FRAME_ADDR_OFFSET + reg_axi_awaddr_4;
                        reg_axi_awaddr_4 <= reg_axi_awaddr_4 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_4 <= reg_axi_awaddr_4;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else begin
                    reg_axi_awaddr_4 <= 'b0;
                    reg_axi_awaddr <= 'b0;
                end
            end
            CH_4: begin
                if(addr_head_flag) begin
                    channel4_addr <= channel4_addr + 1'b1;
                    channel4_data_d1 <= channel4_data;
                end
                else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1) && (burst_len_count < BURST_LEN - 1'b1)) begin
                    channel4_addr <= channel4_addr + 1'b1;
                end
                else begin
                    channel4_addr <= channel4_addr;
                end
                if(frame_end_flag_4) begin 
                    reg_axi_awaddr_4 <= 'b0;                    // 指示帧结束信号来临时，用于累加的地址信号必须清零
                    if(frame_addr_count_4 == 2'd1) begin        // 每帧结束地址偏移计数信号
                        frame_addr_count_4 <= 2'b0;
                    end
                    else begin
                        frame_addr_count_4 <= frame_addr_count_4 + 1'b1;
                    end
                end
                else begin
                    reg_axi_awaddr_4 <= reg_axi_awaddr_4;
                    frame_addr_count_4 <= frame_addr_count_4;
                end
            end
            CH5_WAIT: begin
                if(frame_addr_count_5 == 2'd0) begin
                    if((channel4_rvalid == 1'b1) && (channel5_rready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_5 + reg_axi_awaddr_5;         // 没握手之前生成首地址
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr_5 <= reg_axi_awaddr_5 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_5 <= reg_axi_awaddr_5;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else if(frame_addr_count_5 == 2'd1) begin
                    if((channel5_rvalid == 1'b1) && (channel5_rready == 1'b1)) begin
                        reg_axi_awaddr_5 <= reg_axi_awaddr_5 + BURST_LEN;
                        reg_axi_awaddr <= ADDR_OFFSET_5 + FRAME_ADDR_OFFSET + reg_axi_awaddr_5;
                    end
                    else if((axi_awvalid == 1'b1) && (axi_awready == 1'b1)) begin
                        reg_axi_awaddr <= ADDR_OFFSET_5 + FRAME_ADDR_OFFSET + reg_axi_awaddr_5;
                        reg_axi_awaddr_5 <= reg_axi_awaddr_5 + BURST_LEN;
                    end
                    else begin
                        reg_axi_awaddr_5 <= reg_axi_awaddr_5;
                        reg_axi_awaddr <= reg_axi_awaddr;
                    end
                end
                else begin
                    reg_axi_awaddr_5 <= 'b0;
                    reg_axi_awaddr <= 'b0;
                end
            end
            CH_5: begin
                if(addr_head_flag) begin
                    channel5_addr <= channel5_addr + 1'b1;
                    channel5_data_d1 <= channel5_data;
                end
                else if((axi_wvalid == 1'b1) && (axi_wready == 1'b1) && (burst_len_count < BURST_LEN - 1'b1)) begin
                    channel5_addr <= channel5_addr + 1'b1;
                end
                else begin
                    channel5_addr <= channel5_addr;
                end
                if(frame_end_flag_5) begin 
                    reg_axi_awaddr_5 <= 'b0;                    // 指示帧结束信号来临时，用于累加的地址信号必须清零
                    if(frame_addr_count_5 == 2'd1) begin        // 每帧结束地址偏移计数信号
                        frame_addr_count_5 <= 2'b0;
                    end
                    else begin
                        frame_addr_count_5 <= frame_addr_count_5 + 1'b1;
                    end
                end
                else begin
                    reg_axi_awaddr_5 <= reg_axi_awaddr_5;
                    frame_addr_count_5 <= frame_addr_count_5;
                end
            end
            default: begin
                channel1_addr <= channel1_addr;
                channel2_addr <= channel2_addr;
                channel3_addr <= channel3_addr;
                channel4_addr <= channel4_addr;
                channel5_addr <= channel5_addr;
                frame_addr_count_1 <= frame_addr_count_1;
                frame_addr_count_2 <= frame_addr_count_2;
                frame_addr_count_3 <= frame_addr_count_3;
                frame_addr_count_4 <= frame_addr_count_4;
                frame_addr_count_5 <= frame_addr_count_5;
                reg_axi_awaddr_1 <= reg_axi_awaddr_1;
                reg_axi_awaddr_2 <= reg_axi_awaddr_2;
                reg_axi_awaddr_3 <= reg_axi_awaddr_3;
                reg_axi_awaddr_4 <= reg_axi_awaddr_4;
                reg_axi_awaddr_5 <= reg_axi_awaddr_5;
                reg_axi_awaddr <= reg_axi_awaddr;
                channel1_data_d1 <= 'b0;
                channel2_data_d1 <= 'b0;
                channel3_data_d1 <= 'b0;
                channel4_data_d1 <= 'b0;
                channel5_data_d1 <= 'b0;
            end
        endcase
    end
end


// 数据通道
always @(*) begin
    case(buf_rd_state)
        CH_1: reg_axi_wdata <= pose_axi_wready ? channel1_data_d1 : channel1_data;
        CH_2: reg_axi_wdata <= pose_axi_wready ? channel2_data_d1 : channel2_data;
        CH_3: reg_axi_wdata <= pose_axi_wready ? channel3_data_d1 : channel3_data;
        CH_4: reg_axi_wdata <= pose_axi_wready ? channel4_data_d1 : channel4_data;
        CH_5: reg_axi_wdata <= pose_axi_wready ? channel5_data_d1 : channel5_data;
        default: reg_axi_wdata <= 'b0;
    endcase
end


// 指示 axi 可读
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        axi_rd_en <= 'b0;
    end
    else if(frame_addr_count_4 == 2'd2) begin
        axi_rd_en <= 1'b1;
    end
    else if(frame_addr_count_4 == 2'd1) begin
        axi_rd_en <= 1'b0;
    end
    else begin
        axi_rd_en <= axi_rd_en;
    end
end
                                                                                                                                                                            

endmodule