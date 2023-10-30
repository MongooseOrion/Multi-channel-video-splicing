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
// 从 ddr 中读数据，并送往 hdmi 时序生成模块
//
module axi_arbitrate_rd #(
    parameter MEM_ROW_WIDTH        = 15     ,
    parameter MEM_COLUMN_WIDTH     = 10     ,
    parameter MEM_BANK_WIDTH       = 3      ,
    parameter CTRL_ADDR_WIDTH = MEM_ROW_WIDTH + MEM_BANK_WIDTH + MEM_COLUMN_WIDTH,
    parameter DQ_WIDTH          = 12'd32    ,
    parameter H_HEIGHT = 'd720              ,
    parameter H_WIDTH = 'd1280              ,
    parameter BURST_LEN = 'd20
)(
    input                               clk             ,
    input                               rst             ,

    // 输出数据给 buffer
    input                               axi_wr_buf_wait ,   // 必须提前拉高并持续一段时间
    input  [1:0]                        channel_sel     ,
    output                              buf_wr_en       ,
    output [DQ_WIDTH*8-1:0]             buf_wr_data     ,    
    
    // AXI READ INTERFACE
    output                              axi_arvalid     ,  
    input                               axi_arready     , 
    output [CTRL_ADDR_WIDTH-1:0]        axi_araddr      ,  
    output [3:0]                        axi_arid        ,  
    output [3:0]                        axi_arlen       ,  
    output [2:0]                        axi_arsize      ,  
    output [1:0]                        axi_arburst     ,  
                                                         
    output                              axi_rready      ,  
    input  [DQ_WIDTH*8-1:0]             axi_rdata       ,  
    input                               axi_rvalid      ,  
    input                               axi_rlast       ,  
    input  [3:0]                        axi_rid         
);

parameter WIDTH_QD = H_WIDTH / 4;
parameter HEIGHT_QD = H_HEIGHT / 4;
parameter WIDTH_TC = H_WIDTH * 3/4;
parameter HEIGHT_TC = H_HEIGHT * 3/4;
parameter   WR1_WAIT = 4'b0000,              // AXI 读状态机
            WR_1 = 4'b0001,
            WR2_WAIT = 4'b0010,
            WR_2 = 4'b0011,
            WR3_WAIT = 4'b0100,
            WR_3 = 4'b0101,
            WR4_WAIT = 4'b0110,
            WR_4 = 4'b0111,
            WR5_WAIT = 4'b1000,
            WR_5 = 4'b1001;
// 地址偏移量
parameter FRAME_ADDR_OFFSET = 'd40960;
parameter   ADDR_OFFSET_1 = 'd0,                    // 0-40959, 40960-81919
            ADDR_OFFSET_2 = FRAME_ADDR_OFFSET * 2,  // 81920-122879, 122880-163839
            ADDR_OFFSET_3 = ADDR_OFFSET_2 + 2 * (FRAME_ADDR_OFFSET),      // 
            ADDR_OFFSET_4 = ADDR_OFFSET_3 + 2 * (FRAME_ADDR_OFFSET),
            ADDR_OFFSET_5 = ADDR_OFFSET_4 + 2 * (FRAME_ADDR_OFFSET);

reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr  ;
reg                             reg_axi_arvalid ;
reg                             reg_axi_rready  ;
reg [DQ_WIDTH*8-1:0]            reg_axi_rdata   ;

reg                             hdmi_hsync_1_d1 ;
reg                             hdmi_vsync_1_d1 ;
reg                             frame_en        ;
reg [9:0]                       hsync_count     ;
reg [9:0]                       pix_count_qd    ;
reg [9:0]                       pix_count_tc    ;
reg [3:0]                       buf_wr_state    ;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr_1;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr_2;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr_3;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr_4;
reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr_5;
reg [1:0]                       frame_count_1   ;
reg [1:0]                       frame_count_2   ;
reg [1:0]                       frame_count_3   ;
reg [1:0]                       frame_count_4   ;
reg [1:0]                       frame_count_5   ;

assign axi_arvalid  = reg_axi_arvalid       ;
assign axi_araddr   = reg_axi_araddr        ;
assign axi_awlen    = BURST_LEN - 1'b1      ;   // 突发长度：20
assign axi_awsize   = DQ_WIDTH*8/8          ;   // DATA_LEN = 256
assign axi_awburst  = 2'b01                 ;
assign axi_rready   = 1'b1                  ;

assign buf_wr_en    = axi_rvalid            ;
assign buf_wr_data  = axi_rdata             ;


// 读出数据计数，只计 1/4 行宽度
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        pix_count_qd <= 'b0;
    end
    else if((axi_rready == 1'b1) && (axi_rvalid == 1'b1)) begin
        if(pix_count_qd == WIDTH_QD - 1'b1) begin
            pix_count_qd <= 10'd0;
        end
        else begin
            pix_count_qd <= pix_count_qd + (DQ_WIDTH*8/16);
        end
    end
    else begin
        pix_count_qd <= pix_count_qd;
    end
end


// 状态跳转
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        buf_wr_state <= 'b0;
    end
    else begin
        if(channel_sel == 'd2) begin                    // 如果到了下边的图像
            case(buf_wr_state)
                WR1_WAIT: begin
                    buf_wr_state <= WR5_WAIT;
                end
                WR5_WAIT: begin
                    if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                        buf_wr_state <= WR_5;
                    end
                    else begin
                        buf_wr_state <= WR5_WAIT;
                    end
                end
                WR_5: begin
                    if((pix_count_tc == WIDTH_TC - 1'b1) && (axi_wr_buf_wait == 1'b0)) begin
                        buf_wr_state <= WR1_WAIT;
                    end
                    else if(axi_wr_buf_wait) begin
                        buf_wr_state <= buf_wr_state;
                    end
                    else begin
                        buf_wr_state <= WR5_WAIT;
                    end
                end
                default: buf_wr_state <= buf_wr_state;
            endcase
        end
        else begin                                      // 默认，上边的图像
            case(buf_wr_state)
                WR1_WAIT: begin
                    if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                        buf_wr_state <= WR_1;
                    end
                    else begin
                        buf_wr_state <= WR1_WAIT;
                    end
                end
                WR_1: begin
                    if(pix_count_qd == WIDTH_QD - 1'b1) begin
                        buf_wr_state <= WR2_WAIT;
                    end
                    else begin
                        buf_wr_state <= WR1_WAIT;
                    end
                end
                WR2_WAIT: begin
                    if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                        buf_wr_state <= WR_2;
                    end
                    else begin
                        buf_wr_state <= WR2_WAIT;
                    end
                end
                WR_2: begin
                    if(pix_count_qd == WIDTH_QD - 1'b1) begin
                        buf_wr_state <= WR3_WAIT;
                    end
                    else begin
                        buf_wr_state <= WR2_WAIT;
                    end
                end
                WR3_WAIT: begin
                    if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                        buf_wr_state <= WR_3;
                    end
                    else begin
                        buf_wr_state <= WR3_WAIT;
                    end
                end
                WR_3: begin
                    if(pix_count_qd == WIDTH_QD - 1'b1) begin
                        buf_wr_state <= WR4_WAIT;
                    end
                    else begin
                        buf_wr_state <= WR3_WAIT;
                    end
                end
                WR4_WAIT: begin
                    if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                        buf_wr_state <= WR_4;
                    end
                    else begin
                        buf_wr_state <= WR4_WAIT;
                    end
                end
                WR_4: begin
                    if((pix_count_qd == WIDTH_QD - 1'b1) && (axi_wr_buf_wait == 1'b0)) begin
                        buf_wr_state <= WR1_WAIT;
                    end
                    else if(axi_wr_buf_wait) begin
                        buf_wr_state <= buf_wr_state;
                    end
                    else begin
                        buf_wr_state <= WR4_WAIT;
                    end
                end
                default: buf_wr_state <= WR1_WAIT;
            endcase
        end
    end
end


// 状态机关于握手的相关内部信号
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        reg_axi_arvalid <= 'b0;
    end
    else begin
        case(buf_wr_state)
            WR1_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            WR_1: begin
                if(axi_rlast) begin
                    reg_axi_rready <= 1'b0;
                end
                else if((axi_rvalid == 1'b1) && (axi_rready == 1'b1)) begin
                    reg_axi_rready <= 1'b1;
                end
                else begin
                    reg_axi_rready <= reg_axi_rready;
                end
            end
            WR2_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            WR_2: begin
                if(axi_rlast) begin
                    reg_axi_rready <= 1'b0;
                end
                else if((axi_rvalid == 1'b1) && (axi_rready == 1'b1)) begin
                    reg_axi_rready <= 1'b1;
                end
                else begin
                    reg_axi_rready <= reg_axi_rready;
                end
            end
            WR3_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            WR_3: begin
                if(axi_rlast) begin
                    reg_axi_rready <= 1'b0;
                end
                else if((axi_rvalid == 1'b1) && (axi_rready == 1'b1)) begin
                    reg_axi_rready <= 1'b1;
                end
                else begin
                    reg_axi_rready <= reg_axi_rready;
                end
            end
            WR4_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            WR_4: begin
                if(axi_rlast) begin
                    reg_axi_rready <= 1'b0;
                end
                else if((axi_rvalid == 1'b1) && (axi_rready == 1'b1)) begin
                    reg_axi_rready <= 1'b1;
                end
                else begin
                    reg_axi_rready <= reg_axi_rready;
                end
            end
            WR5_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            WR_5: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    reg_axi_arvalid <= 1'b1;
                end
            end
            default: reg_axi_arvalid <= 1'b1;
        endcase
    end
end


// 状态机内部信号
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        reg_axi_araddr_1 <= 'b0;
        reg_axi_araddr_2 <= 'b0;
        reg_axi_araddr_3 <= 'b0;
        reg_axi_araddr_4 <= 'b0;
        reg_axi_araddr_5 <= 'b0;
        reg_axi_araddr <= 'b0;
        frame_count_1 <= 'b0;
        frame_count_2 <= 'b0;
        frame_count_3 <= 'b0;
        frame_count_4 <= 'b0;
        frame_count_5 <= 'b0;
    end
    else begin
        case(buf_wr_state)
            WR1_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    if(reg_axi_araddr_1 < (WIDTH_QD * HEIGHT_QD) / 256) begin   // 通过地址判断当前像素数量
                        reg_axi_araddr_1 <= reg_axi_araddr_1 + BURST_LEN;
                    end
                    else begin
                        if(frame_count_1 == 1'b1) begin                         // 帧计数
                            frame_count_1 <= 2'b0;
                        end
                        else begin
                            frame_count_1 <= frame_count_1 + 1'b1;
                        end
                        reg_axi_araddr_1 <= 'b0;
                    end
                end
                else begin
                    reg_axi_araddr_1 <= reg_axi_araddr_1;
                end
                if(frame_count_1 == 2'b0) begin                     // 帧 1 使用基地址 1
                    reg_axi_araddr <= ADDR_OFFSET_1 + reg_axi_araddr_1;
                end
                else if(frame_count_1 == 2'b1) begin                // 帧 2 使用基地址 2
                    reg_axi_araddr <= ADDR_OFFSET_1 + FRAME_ADDR_OFFSET + reg_axi_araddr_1;
                end
                else begin
                    reg_axi_araddr <= reg_axi_araddr_1;
                end
            end
            WR2_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    if(reg_axi_araddr_2 < (WIDTH_QD * HEIGHT_QD) / 256) begin   // 通过地址判断当前像素数量
                        reg_axi_araddr_2 <= reg_axi_araddr_2 + BURST_LEN;
                    end
                    else begin
                        if(frame_count_2 == 1'b1) begin                         // 帧计数
                            frame_count_2 <= 2'b0;
                        end
                        else begin
                            frame_count_2 <= frame_count_2 + 1'b1;
                        end
                        reg_axi_araddr_2 <= 'b0;
                    end
                end
                else begin
                    reg_axi_araddr_2 <= reg_axi_araddr_2;
                end
                if(frame_count_2 == 2'b0) begin                     // 帧 1 使用基地址 1
                    reg_axi_araddr <= ADDR_OFFSET_2 + reg_axi_araddr_2;
                end
                else if(frame_count_2 == 2'b1) begin                // 帧 2 使用基地址 2
                    reg_axi_araddr <= ADDR_OFFSET_2 + FRAME_ADDR_OFFSET + reg_axi_araddr_2;
                end
                else begin
                    reg_axi_araddr <= reg_axi_araddr_2;
                end
            end
            WR3_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    if(reg_axi_araddr_3 < (WIDTH_QD * HEIGHT_QD) / 256) begin   // 通过地址判断当前像素数量
                        reg_axi_araddr_3 <= reg_axi_araddr_3 + BURST_LEN;
                    end
                    else begin
                        if(frame_count_3 == 1'b1) begin                         // 帧计数
                            frame_count_3 <= 2'b0;
                        end
                        else begin
                            frame_count_3 <= frame_count_3 + 1'b1;
                        end
                        reg_axi_araddr_3 <= 'b0;
                    end
                end
                else begin
                    reg_axi_araddr_3 <= reg_axi_araddr_3;
                end
                if(frame_count_3 == 2'b0) begin                     // 帧 1 使用基地址 1
                    reg_axi_araddr <= ADDR_OFFSET_3 + reg_axi_araddr_3;
                end
                else if(frame_count_3 == 2'b1) begin                // 帧 2 使用基地址 2
                    reg_axi_araddr <= ADDR_OFFSET_3 + FRAME_ADDR_OFFSET + reg_axi_araddr_3;
                end
                else begin
                    reg_axi_araddr <= reg_axi_araddr_3;
                end
            end
            WR4_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    if(reg_axi_araddr_4 < (WIDTH_QD * HEIGHT_QD) / 256) begin   // 通过地址判断当前像素数量
                        reg_axi_araddr_4 <= reg_axi_araddr_4 + BURST_LEN;
                    end
                    else begin
                        if(frame_count_4 == 1'b1) begin                         // 帧计数
                            frame_count_4 <= 2'b0;
                        end
                        else begin
                            frame_count_4 <= frame_count_4 + 1'b1;
                        end
                        reg_axi_araddr_4 <= 'b0;
                    end
                end
                else begin
                    reg_axi_araddr_4 <= reg_axi_araddr_4;
                end
                if(frame_count_4 == 2'b0) begin                     // 帧 1 使用基地址 1
                    reg_axi_araddr <= ADDR_OFFSET_4 + reg_axi_araddr_4;
                end
                else if(frame_count_4 == 2'b1) begin                // 帧 2 使用基地址 2
                    reg_axi_araddr <= ADDR_OFFSET_4 + FRAME_ADDR_OFFSET + reg_axi_araddr_4;
                end
                else begin
                    reg_axi_araddr <= reg_axi_araddr_4;
                end
            end
            WR5_WAIT: begin
                if((axi_arready == 1'b1) && (axi_arvalid == 1'b1)) begin
                    if(reg_axi_araddr_5 < (WIDTH_TC * HEIGHT_TC) / 256) begin   // 通过地址判断当前像素数量
                        reg_axi_araddr_5 <= reg_axi_araddr_5 + BURST_LEN;
                    end
                    else begin
                        if(frame_count_5 == 1'b1) begin                         // 帧计数
                            frame_count_5 <= 2'b0;
                        end
                        else begin
                            frame_count_5 <= frame_count_5 + 1'b1;
                        end
                        reg_axi_araddr_5 <= 'b0;
                    end
                end
                else begin
                    reg_axi_araddr_5 <= reg_axi_araddr_5;
                end
                if(frame_count_5 == 2'b0) begin                     // 帧 1 使用基地址 1
                    reg_axi_araddr <= ADDR_OFFSET_5 + reg_axi_araddr_5;
                end
                else if(frame_count_5 == 2'b1) begin                // 帧 2 使用基地址 2
                    reg_axi_araddr <= ADDR_OFFSET_5 + FRAME_ADDR_OFFSET + reg_axi_araddr_5;
                end
                else begin
                    reg_axi_araddr <= reg_axi_araddr_5;
                end
            end
            default: begin
                reg_axi_araddr_1 <= 'b0;
                reg_axi_araddr_2 <= 'b0;
                reg_axi_araddr_3 <= 'b0;
                reg_axi_araddr_4 <= 'b0;
                reg_axi_araddr_5 <= 'b0;
                reg_axi_araddr <= 'b0;
                frame_count_1 <= 'b0;
                frame_count_2 <= 'b0;
                frame_count_3 <= 'b0;
                frame_count_4 <= 'b0;
                frame_count_5 <= 'b0;
            end
        endcase
    end
end


endmodule