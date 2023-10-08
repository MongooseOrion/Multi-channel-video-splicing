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
// 图像缩放
//
module image_scale#(
    parameter COL_PIXEL = 'd1280*3/4,
    parameter ROW_PIXEL = 'd720*3/4
)(
    input           clk,
    input           rst,
    input  [7:0]    command_in,
    output [15:0]   rd_addr,      //读地址
    input  [15:0]   data_in, 
    input  [9:0]    row_end_flag,   
    input  [9:0]    frame_end_flag,    
    
    output [15:0]   data_out      //缩放后的数据输出，在其它模块信号同步打拍
);

parameter COL_OFFSET = ;    //显示起始行坐标
parameter IMG_y=68;

wire     [8:0]    cnt_col;            //图片显示区域的行计数
wire     [8:0]    cnt_row;            //图片显示区域的场计数
reg      [8:0]    zoom_In_x;          //放大后的坐标映射
reg      [8:0]    zoom_In_y;
wire     [8:0]    zoom_x;             //最终缩放后坐标映射
wire     [8:0]    zoom_y;
wire    display_value;                //图像有效显示区域

assign cnt_col = hcount >= IMG_x ? hcount-IMG_x : 0;    
assign cnt_row = vcount >= IMG_y ? vcount-IMG_y : 0;    

//=======================放大坐标映射==============================        
//偏移量公式：+ [side*(n-1)/2]，n为放大倍数  side为图像的宽、高
always @(*) begin
    case(Zoom_In)
        2'b00   : begin                                     //原图
                    zoom_In_x = cnt_col;
                    zoom_In_y = cnt_row;
                  end
        2'b01   : begin                                     //2倍
                    zoom_In_x = (cnt_col+120)>>1;
                    zoom_In_y = (cnt_row+68)>>1;
                  end
        2'b10   : begin                                     //4倍
                    zoom_In_x = (cnt_col+360)>>2;
                    zoom_In_y = (cnt_row+204)>>2;
                  end
        2'b11   : begin                                     //8倍
                    zoom_In_x = (cnt_col+840)>>3;
                    zoom_In_y = (cnt_row+476)>>3;
                  end
        default : begin
                    zoom_In_x = cnt_col;
                    zoom_In_y = cnt_row;
                  end
    endcase
end


//-------------------缩小坐标映射--------------------------------
//直接利用移位来达到缩小倍数的需求。串接在放大映射坐标后，可以在实现分辨率下采样（减小）的局部放大
assign zoom_x = zoom_In_x << Zoom_Out;
assign zoom_y = zoom_In_y << Zoom_Out;

//---------------------------------------------------
//由于缩小会使分辨率减小，原显示区域会出现缩小倍数^2的图像阵列，所以只显示左上角第一个缩小图像
assign display_value =  (hcount >= IMG_x && hcount < IMG_x+(COL>>Zoom_Out)) && (vcount >= IMG_y && vcount < IMG_y+(ROW>>Zoom_Out));    

assign read_addr = zoom_y * COL + zoom_x;            //缩放映射后的 RAM 地址
assign data_out = display_value ? data_in : 0;       //有效显示区域输出图像，无效背景为黑

endmodule        