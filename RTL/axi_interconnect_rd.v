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

    input                               init_tc_done    ,
    input                               init_qd_done    ,
    input                               processing_wait ,
    output reg                          wait_proceed    ,

    // 输出数据给 buffer
    input                               frame_instruct  ,       // 0 为 1,2 帧，1 为 3,4 帧
    output reg                          buf_wr_en_1     /*synthesis PAP_MARK_DEBUG="1"*/,
    output reg  [DQ_WIDTH*8-1:0]        buf_wr_data_1   /*synthesis PAP_MARK_DEBUG="1"*/,
    output reg                          buf_wr_en_2     ,
    output reg  [DQ_WIDTH*8-1:0]        buf_wr_data_2   , 
    output reg                          sel_part        ,   
    
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
            WR1_PRE = 4'b0001,
            WR1_ADDR = 4'b0010,
            WR2_PRE = 4'b0011,
            WR2_ADDR = 4'b0100,
            WR3_PRE = 4'b0101,
            WR3_ADDR = 4'b0110,
            WR4_PRE = 4'b0111,
            WR4_ADDR = 4'b1000,
            WR5_PRE = 4'b1001,
            WR5_ADDR = 4'b1010;
// 地址偏移量
parameter FRAME_ADDR_OFFSET_1 = 'd30_000;
parameter FRAME_ADDR_OFFSET_2 = 'd260_000;
parameter   ADDR_OFFSET_1 = 'd0,                    
            ADDR_OFFSET_2 = FRAME_ADDR_OFFSET_1 * 2,  
            ADDR_OFFSET_3 = ADDR_OFFSET_2 + 2 * (FRAME_ADDR_OFFSET_1),      // 
            ADDR_OFFSET_4 = ADDR_OFFSET_3 + 2 * (FRAME_ADDR_OFFSET_1),
            ADDR_OFFSET_5 = ADDR_OFFSET_4 + 2 * (FRAME_ADDR_OFFSET_1);
parameter ADDR_STEP = BURST_LEN * 8;       // 首地址自增步长，1 个地址 32 位数据，这与芯片的 DQ 宽度有关

wire                            nege_vsync      ;
wire                            pose_vsync      ;
wire                            nege_href       ;
wire                            pose_arvalid    ;

reg [CTRL_ADDR_WIDTH-1:0]       reg_axi_araddr  /*synthesis PAP_MARK_DEBUG="1"*/;
reg                             reg_axi_arvalid ;
reg                             reg_axi_rready  ;
reg [DQ_WIDTH*8-1:0]            reg_axi_rdata   ;

reg                             reg_vsync_d1        ;
reg                             reg_vsync_d2        ;
reg                             reg_href_d1         ;
reg                             reg_href_d2         ;
reg                             axi_arvalid_temp    ;
reg                             axi_rd_en           ;
reg [3:0]                       addr_state          ;
reg [15:0]                      reg_axi_araddr_1    ;
reg [15:0]                      reg_axi_araddr_2    ;
reg [15:0]                      reg_axi_araddr_3    ;
reg [15:0]                      reg_axi_araddr_4    ;
reg [19:0]                      reg_axi_araddr_5    ;
reg                             row_end_flag        ;
reg [10:0]                      row_count_1         ;
reg [10:0]                      row_count_2         ;
reg [15:0]                      rlast_count         ;

assign axi_arvalid  = reg_axi_arvalid       ;
assign axi_araddr   = reg_axi_araddr        ;
assign axi_arlen    = BURST_LEN - 1'b1      ;   // 突发长度
assign axi_arsize   = DQ_WIDTH*8/8          ;   // DATA_LEN = 256
assign axi_arburst  = 2'b01                 ;
assign axi_rready   = 1'b1                  ;

assign pose_vsync = ((reg_vsync_d1) && (~reg_vsync_d2)) ? 1'b1 : 1'b0;
assign nege_vsync = ((~reg_vsync_d1) && (reg_vsync_d2)) ? 1'b1 : 1'b0;
assign nege_href = ((~reg_href_d1) && (reg_href_d2)) ? 1'b1 : 1'b0;
assign pose_arvalid = ((axi_arvalid_temp) && (~axi_arvalid)) ? 1'b1 : 1'b0;


// 延迟时钟周期，跨时钟信号应延迟两个周期，确保基于它们创建的任何信号符合时序要求
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        reg_vsync_d1 <= 'b0;
        reg_vsync_d2 <= 'b0;
        reg_href_d1 <= 'b0;
        reg_href_d2 <= 'b0;
    end
    else begin
        reg_vsync_d1 <= hdmi_vsync;
        reg_vsync_d2 <= reg_vsync_d1;
        reg_href_d1 <= hdmi_href;
        reg_href_d2 <= reg_href_d1;
    end
end


// 读使能信号，在场同步下降沿或者行有效下降沿开始读，读一行后停止
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        axi_rd_en <= 'b0;
    end
    else if((init_qd_done)
            && ((nege_vsync == 1'b1) || (nege_href == 1'b1))) begin
        axi_rd_en <= 1'b1;
    end
    else if(row_end_flag) begin
        axi_rd_en <= 1'b0;
    end
    else begin
        axi_rd_en <= axi_rd_en;
    end
end


// 使用状态机生成地址
// 状态机跳转条件
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        addr_state <= 'b0;
    end
    else if(axi_rd_en) begin
        case(addr_state)
            INIT_WAIT: begin
                if(processing_wait) begin
                    addr_state <= INIT_WAIT;
                end
                else begin
                    addr_state <= WR1_LINK;
                end
            end
            WR1_LINK: begin
                if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                    addr_state <= WR1_ADDR;
                end
                else begin
                    addr_state <= WR1_LINK;
                end
            end
            WR1_ADDR: begin
                if((reg_axi_araddr_1 - ADDR_STEP) % (WIDTH_QD / 2) == 'b0) begin
                    addr_state <= WR2_LINK;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR2_LINK: begin
                if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                    addr_state <= WR2_ADDR;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR2_ADDR: begin
                if((reg_axi_araddr_2 - ADDR_STEP) % (WIDTH_QD / 2) == 'b0) begin
                    addr_state <= WR3_LINK;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR3_LINK: begin
                if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                    addr_state <= WR3_ADDR;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR3_ADDR: begin
                if((reg_axi_araddr_3 - ADDR_STEP) % (WIDTH_QD / 2) == 'b0) begin
                    addr_state <= WR4_LINK;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR4_LINK: begin
                if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                    addr_state <= WR4_ADDR;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR4_ADDR: begin
                if(((reg_axi_araddr_4 - ADDR_STEP) % (WIDTH_QD / 2) == 'b0)
                    && (processing_wait == 1'b0)) begin
                    if(row_count_1 == 'd0) begin
                        addr_state <= WR5_LINK;
                    end
                    else begin
                        addr_state <= WR1_LINK;
                    end
                end
                else if(((reg_axi_araddr_4 - ADDR_STEP) % WIDTH_QD == 'b0)
                    && (processing_wait == 1'b1)) begin
                    addr_state <= INIT_WAIT;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR5_LINK: begin
                if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                    addr_state <= WR5_ADDR;
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            WR5_ADDR: begin
                if((reg_axi_araddr_5 - ADDR_STEP) % WIDTH_QD == 'b0) begin
                    if(row_count_2 == 'd0) begin
                        addr_state <= WR1_LINK;
                    end
                    else begin
                        addr_state <= addr_state;
                    end
                end
                else begin
                    addr_state <= addr_state;
                end
            end
            default: begin
                addr_state <= INIT_WAIT;
            end
        endcase
    end
    else begin
        addr_state <= addr_state;
    end
end

// 状态机内部信号
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        wait_proceed <= 'b0;
        reg_axi_araddr <= 'b0;
        reg_axi_araddr_1 <= 'b0;
        reg_axi_araddr_2 <= 'b0;
        reg_axi_araddr_3 <= 'b0;
        reg_axi_araddr_4 <= 'b0;
        reg_axi_araddr_5 <= 'b0;
        reg_axi_arvalid <= 'b0;
        row_end_flag <= 'b0;
        row_count_1 <= 'b0;
        row_count_2 <= 'b0;
    end
    else if(nege_vsync) begin
        reg_axi_araddr_1 <= 'b0;
        reg_axi_araddr_2 <= 'b0;
        reg_axi_araddr_3 <= 'b0;
        reg_axi_araddr_4 <= 'b0;
        reg_axi_araddr_5 <= 'b0;
    end
    else if(axi_rd_en) begin
        case(addr_state)
            INIT_WAIT: begin
                if(processing_wait) begin
                    wait_proceed <= 1'b1;
                end
                else begin
                    wait_proceed <= 1'b0;
                end
            end
            WR1_LINK: begin
                // 握手设置
                if(axi_arready) begin
                    axi_arvalid_temp <= 1'b0;
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    axi_arvalid_temp <= 1'b1;
                    reg_axi_arvalid <= axi_arvalid_temp;
                end
                // 地址设置
                if(frame_instruct == 1'b0) begin
                    if(pose_arvalid) begin                          // 在没握手之前应先给出地址
                        reg_axi_araddr <= ADDR_OFFSET_1 + reg_axi_araddr_1;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_1 <= reg_axi_araddr_1 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_1 <= reg_axi_araddr_1;
                    end
                end
                else if(frame_instruct == 1'b1) begin
                    if(pose_arvalid) begin
                        reg_axi_araddr <= ADDR_OFFSET_1 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_1;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_1 <= reg_axi_araddr_1 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_1 <= reg_axi_araddr_1;
                    end
                end
            end
            WR1_ADDR: begin
                if((reg_axi_araddr_1 - ADDR_STEP) % WIDTH_QD == 'b0) begin
                    reg_axi_araddr <= reg_axi_araddr;
                    reg_axi_araddr_1 <= reg_axi_araddr_1;
                end
                else begin
                    if(frame_instruct == 1'b0) begin
                        reg_axi_araddr <= ADDR_OFFSET_1 + reg_axi_araddr_1; // 加的是上一次的更改
                        reg_axi_araddr_1 <= reg_axi_araddr_1 + ADDR_STEP;   // 为下一次做的更改
                    end
                    else if(frame_instruct == 1'b1) begin
                        reg_axi_araddr <= ADDR_OFFSET_1 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_1;
                        reg_axi_araddr_1 <= reg_axi_araddr_1 + ADDR_STEP;
                    end
                end
            end
            WR2_LINK: begin
                // 握手设置
                if(axi_arready) begin
                    axi_arvalid_temp <= 1'b0;
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    axi_arvalid_temp <= 1'b1;
                    reg_axi_arvalid <= axi_arvalid_temp;
                end
                // 地址设置
                if(frame_instruct == 1'b0) begin
                    if(pose_arvalid) begin                          // 在没握手之前应先给出地址
                        reg_axi_araddr <= ADDR_OFFSET_2 + reg_axi_araddr_2;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_2 <= reg_axi_araddr_2 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_2 <= reg_axi_araddr_2;
                    end
                end
                else if(frame_instruct == 1'b1) begin
                    if(pose_arvalid) begin
                        reg_axi_araddr <= ADDR_OFFSET_2 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_2;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_2 <= reg_axi_araddr_2 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_2 <= reg_axi_araddr_2;
                    end
                end
            end
            WR2_ADDR: begin
                if((reg_axi_araddr_2 - ADDR_STEP) % WIDTH_QD == 'b0) begin
                    reg_axi_araddr <= reg_axi_araddr;
                    reg_axi_araddr_2 <= reg_axi_araddr_2;
                end
                else begin
                    if(frame_instruct == 1'b0) begin
                        reg_axi_araddr <= ADDR_OFFSET_2 + reg_axi_araddr_2; // 加的是上一次的更改
                        reg_axi_araddr_2 <= reg_axi_araddr_2 + ADDR_STEP;   // 为下一次做的更改
                    end
                    else if(frame_instruct == 1'b1) begin
                        reg_axi_araddr <= ADDR_OFFSET_2 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_2;
                        reg_axi_araddr_2 <= reg_axi_araddr_2 + ADDR_STEP;
                    end
                end
            end
            WR3_LINK: begin
                // 握手设置
                if(axi_arready) begin
                    axi_arvalid_temp <= 1'b0;
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    axi_arvalid_temp <= 1'b1;
                    reg_axi_arvalid <= axi_arvalid_temp;
                end
                // 地址设置
                if(frame_instruct == 1'b0) begin
                    if(pose_arvalid) begin                          // 在没握手之前应先给出地址
                        reg_axi_araddr <= ADDR_OFFSET_3 + reg_axi_araddr_3;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_3 <= reg_axi_araddr_3 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_3 <= reg_axi_araddr_3;
                    end
                end
                else if(frame_instruct == 1'b1) begin
                    if(pose_arvalid) begin
                        reg_axi_araddr <= ADDR_OFFSET_3 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_3;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_3 <= reg_axi_araddr_3 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_3 <= reg_axi_araddr_3;
                    end
                end
            end
            WR3_ADDR: begin
                if((reg_axi_araddr_3 - ADDR_STEP) % WIDTH_QD == 'b0) begin
                    reg_axi_araddr <= reg_axi_araddr;
                    reg_axi_araddr_3 <= reg_axi_araddr_3;
                end
                else begin
                    if(frame_instruct == 1'b0) begin
                        reg_axi_araddr <= ADDR_OFFSET_3 + reg_axi_araddr_3; // 加的是上一次的更改
                        reg_axi_araddr_3 <= reg_axi_araddr_3 + ADDR_STEP;   // 为下一次做的更改
                    end
                    else if(frame_instruct == 1'b1) begin
                        reg_axi_araddr <= ADDR_OFFSET_3 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_3;
                        reg_axi_araddr_3 <= reg_axi_araddr_3 + ADDR_STEP;
                    end
                end
            end
            WR4_LINK: begin
                // 握手设置
                if(axi_arready) begin
                    axi_arvalid_temp <= 1'b0;
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    axi_arvalid_temp <= 1'b1;
                    reg_axi_arvalid <= axi_arvalid_temp;
                end
                // 地址设置
                if(frame_instruct == 1'b0) begin
                    if(pose_arvalid) begin                          // 在没握手之前应先给出地址
                        reg_axi_araddr <= ADDR_OFFSET_4 + reg_axi_araddr_4;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_4 <= reg_axi_araddr_4 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_4 <= reg_axi_araddr_4;
                    end
                end
                else if(frame_instruct == 1'b1) begin
                    if(pose_arvalid) begin
                        reg_axi_araddr <= ADDR_OFFSET_4 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_4;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_4 <= reg_axi_araddr_4 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_4 <= reg_axi_araddr_4;
                    end
                end
            end
            WR4_ADDR: begin
                if((reg_axi_araddr_4 - ADDR_STEP) % WIDTH_QD == 'b0) begin
                    reg_axi_araddr <= reg_axi_araddr;
                    reg_axi_araddr_4 <= reg_axi_araddr_4;
                    row_end_flag <= 1'b0;
                end
                else begin
                    if(frame_instruct == 1'b0) begin
                        reg_axi_araddr <= ADDR_OFFSET_4 + reg_axi_araddr_4; // 加的是上一次的更改
                        reg_axi_araddr_4 <= reg_axi_araddr_4 + ADDR_STEP;   // 为下一次做的更改
                    end
                    else if(frame_instruct == 1'b1) begin
                        reg_axi_araddr <= ADDR_OFFSET_4 + FRAME_ADDR_OFFSET_1 + reg_axi_araddr_4;
                        reg_axi_araddr_4 <= reg_axi_araddr_4 + ADDR_STEP;
                    end
                    if(reg_axi_araddr_4 % WIDTH_QD == 'b0) begin
                        row_end_flag <= 1'b1;                               // 行结束，在此状态结束前一个周期拉高
                        if(row_count_1 == HEIGHT_QD - 1'b1) begin           // 行计数
                            row_count_1 <= 'b0;
                        end
                        else begin
                            row_count_1 <= row_count_1 + 1'b1;
                        end
                    end
                end
            end
            WR5_LINK: begin
                // 握手设置
                if(axi_arready) begin
                    axi_arvalid_temp <= 1'b0;
                    reg_axi_arvalid <= 1'b0;
                end
                else begin
                    axi_arvalid_temp <= 1'b1;
                    reg_axi_arvalid <= axi_arvalid_temp;
                end
                // 地址设置
                if(frame_instruct == 1'b0) begin
                    if(pose_arvalid) begin                          // 在没握手之前应先给出地址
                        reg_axi_araddr <= ADDR_OFFSET_5 + reg_axi_araddr_5;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_5 <= reg_axi_araddr_5 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_5 <= reg_axi_araddr_5;
                    end
                end
                else if(frame_instruct == 1'b1) begin
                    if(pose_arvalid) begin
                        reg_axi_araddr <= ADDR_OFFSET_5 + FRAME_ADDR_OFFSET_2 + reg_axi_araddr_5;
                    end
                    else if((axi_arvalid == 1'b1) && (axi_arready == 1'b1)) begin
                        reg_axi_araddr_5 <= reg_axi_araddr_5 + ADDR_STEP;
                    end
                    else begin
                        reg_axi_araddr <= reg_axi_araddr;
                        reg_axi_araddr_5 <= reg_axi_araddr_5;
                    end
                end
            end
            WR5_ADDR: begin
                if((reg_axi_araddr_5 - ADDR_STEP) % WIDTH_TC == 'b0) begin
                    reg_axi_araddr <= reg_axi_araddr;
                    reg_axi_araddr_5 <= reg_axi_araddr_5;
                    row_end_flag <= 1'b0;
                end
                else begin
                    if(frame_instruct == 1'b0) begin
                        reg_axi_araddr <= ADDR_OFFSET_5 + reg_axi_araddr_5; // 加的是上一次的更改
                        reg_axi_araddr_5 <= reg_axi_araddr_5 + ADDR_STEP;   // 为下一次做的更改
                    end
                    else if(frame_instruct == 1'b1) begin
                        reg_axi_araddr <= ADDR_OFFSET_5 + FRAME_ADDR_OFFSET_2 + reg_axi_araddr_5;
                        reg_axi_araddr_5 <= reg_axi_araddr_5 + ADDR_STEP;
                    end
                    if(reg_axi_araddr_5 % WIDTH_TC == 'b0) begin
                        row_end_flag <= 1'b1;
                        if(row_count_2 == HEIGHT_TC - 1'b1) begin               // 行计数
                            row_count_2 <= 'b0;
                        end
                        else begin
                            row_count_2 <= row_count_2 + 1'b1;
                        end
                    end
                end
            end
            default: begin
                wait_proceed <= wait_proceed;
                reg_axi_araddr <= reg_axi_araddr;
                reg_axi_araddr_1 <= reg_axi_araddr_1;
                reg_axi_araddr_2 <= reg_axi_araddr_2;
                reg_axi_araddr_3 <= reg_axi_araddr_3;
                reg_axi_araddr_4 <= reg_axi_araddr_4;
                reg_axi_araddr_5 <= reg_axi_araddr_5;
                reg_axi_arvalid <= reg_axi_arvalid;
                row_end_flag <= row_end_flag;
                row_count_1 <= row_count_1;
                row_count_2 <= row_count_2;
            end
        endcase
    end
end


// 输出像素统计
// 对应关系：(rlast_count + 1) * 160
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        rlast_count <= 'b0;
    end
    else if(axi_rlast) begin
        if(rlast_count == H_WIDTH * H_HEIGHT / (ADDR_STEP * 2) - 1'b1) begin
            rlast_count <= 'b0;
        end
        else begin
            rlast_count <= rlast_count + 1'b1;
        end
    end
end


// 指示当前数据为上还是下
always @(posedge clk or negedge rst) begin
    if(!rst) begin
        sel_part <= 'b0;
    end
    else if(rlast_count >= H_WIDTH * HEIGHT_QD) begin
        sel_part <= 1'b1;
    end
    else begin
        sel_part <= 1'b0;
    end
end


// 输出数据有效信号和数据信号
always @(*) begin
    buf_wr_en_1 <= (sel_part == 1'b0) ? axi_rvalid : 1'b0;
    buf_wr_data_1 <= (sel_part == 1'b0) ? axi_rdata : 'b0;
    buf_wr_en_2 <= (sel_part == 1'b1) ? axi_rvalid : 1'b0;
    buf_wr_data_2 <= (sel_part == 1'b1) ? axi_rdata : 'd0;
end


endmodule