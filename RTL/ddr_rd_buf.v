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
// 将 ddr 读出的数据缓存到 buf，并为 hdmi 输出做准备
//
module ddr_rd_buf #(
    parameter DQ_WIDTH  = 12'd32    ,
    parameter H_HEIGHT  = 'd720     ,
    parameter H_WIDTH   = 'd1280              
)(
    input                           clk             ,
    input                           rst             ,

    input                           buf_wr_en_1     ,
    input       [DQ_WIDTH*8-1:0]    buf_wr_data_1   ,
    input                           buf_wr_en_2     ,
    input       [DQ_WIDTH*8-1:0]    buf_wr_data_2   ,
    input                           sel_part        ,

    input                           rd_clk          ,
    input                           rd_rst          ,
    input                           rd_en           ,
    input                           rd_fsync        ,
    output reg                      de_o            ,
    output reg  [15:0]              rgb565_out_1    ,
    output reg  [15:0]              rgb565_out_2    
);

parameter WIDTH_QD = H_WIDTH / 4;
parameter HEIGHT_QD = H_HEIGHT / 4;
parameter WIDTH_TC = (H_WIDTH / 4) * 3;
parameter HEIGHT_TC = (H_HEIGHT / 4) * 3;

wire                nege_href       ;
wire [15:0]         rd_data_1       ;
wire [15:0]         rd_data_2       ;

reg                 rd_en_d1        ;
reg                 rd_en_d2        ;
reg                 rd_en_1         ;
reg                 rd_en_2         ;
reg [10:0]          row_count       ;


// 上部分
fifo_rd_buf_1 rd_buf_1(
    .wr_clk         (clk),                // input
    .wr_rst         (rst),                // input
    .wr_en          (buf_wr_en_1),                  // input
    .wr_data        (buf_wr_data_1),              // input [255:0]
    .wr_full        (),              // output
    .almost_full    (),      // output
    .rd_clk         (rd_clk),                // input
    .rd_rst         (rd_rst),                // input
    .rd_en          (rd_en_1),                  // input
    .rd_data        (rd_data_1),              // output [15:0]
    .rd_empty       (),            // output
    .almost_empty   ()     // output
);

// 下部分
fifo_rd_buf_2 rd_buf_2(
    .wr_clk         (clk),                // input
    .wr_rst         (rst),                // input
    .wr_en          (buf_wr_en_2),                  // input
    .wr_data        (buf_wr_data_2),              // input [255:0]
    .wr_full        (),              // output
    .almost_full    (),      // output
    .rd_clk         (rd_clk),                // input
    .rd_rst         (rd_rst),                // input
    .rd_en          (rd_en_2),                  // input
    .rd_data        (rd_data_2),              // output [15:0]
    .rd_empty       (),            // output
    .almost_empty   ()     // output
);


// 读使能
always @(*) begin
    rd_en_1 <= (row_count < HEIGHT_QD) ? rd_en : 1'b0;
    rd_en_2 <= (row_count >= HEIGHT_QD) ? rd_en : 1'b0;
end


// 读使能（行有效）下降沿
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        rd_en_d1 <= 'b0;
    end
    else begin
        rd_en_d1 <= rd_en;
    end
end
assign nege_href = ((~rd_en) && (rd_en_d2)) ? 1'b1 : 1'b0;


// 读出行数计数
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        row_count <= 'b0;
    end
    else if(nege_href) begin
        if(row_count == H_HEIGHT - 1'b1) begin
            row_count <= 11'b0;
        end
        else begin
            row_count <= row_count + 1'b1;
        end
    end
    else begin
        row_count <= row_count;
    end
end


// 最终的输出像素数据
always @(*) begin
    rgb565_out_1 <= (row_count < HEIGHT_QD) ? rd_data_1 : 16'b0;
    rgb565_out_2 <= (row_count >= HEIGHT_QD) ? rd_data_2 : 16'b0;
end


// 输出实际的使能信号
always @(posedge rd_clk or negedge rd_rst) begin
    if(!rd_rst) begin
        de_o <= 'b0;
    end
    else begin
        de_o <= rd_en;
    end
end


endmodule