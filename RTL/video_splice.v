module video_splice(
   input                clk,
   input                rst,

   // cmos1	
   input                cmos1_pclk,    // 像素时钟
   input                cmos1_de,      // 行同步
   input                cmos1_vs,      // 场同步
   input       [15:0]   cmos1_data,    // rgb565 数据
   // cmos2
   input                cmos2_pclk,    // 像素时钟
   input                cmos2_de,      // 行同步
   input                cmos2_vs,      // 场同步
   input       [15:0]   cmos2_data,    // rgb565 数据
   // cmos3
   input                cmos3_pclk,    // 像素时钟
   input                cmos3_de,      // 行同步
   input                cmos3_vs,      // 场同步
   input       [15:0]   cmos3_data,    // rgb565 数据
   // cmos4
   input                cmos4_pclk,    // 像素时钟
   input                cmos4_de,      // 行同步
   input                cmos4_vs,      // 场同步
   input       [15:0]   cmos4_data,    // rgb565 数据

   // output
   output               global_pclk,
   output               global_de,
   output               global_vs,
   output               global_data
   );





   
endmodule