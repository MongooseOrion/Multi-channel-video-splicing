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
* ========================================================================
*/
//
// UART 指令控制模块

module uart_trans(
    input           clk,
    input           rst,  
    input           uart_rx,
    input   [7:0]   command_in,   
    output          uart_tx,
    output  [7:0]   command_out
);


uart_rx command_recv(
    .clk            (clk),
    .rst            (rst),
    .data_out       (command_out),
    .data_out_flag  (),
    .uart_rx        (uart_rx)
);

uart_tx command_deliver(
    .clk            (clk),
    .rst            (rst),
    .data_in        (command_in),
    .data_in_flag   (data_in_flag),
    .uart_tx        (uart_tx)
);


endmodule