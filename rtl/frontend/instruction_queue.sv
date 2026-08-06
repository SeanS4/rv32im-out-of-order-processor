module instruction_queue
import rv32i_types::*;
#(
    parameter integer length = 8,
    parameter type width = iq_package
)
(
    input   logic               clk,
    input   logic               rst,
	output logic full, empty,  // high when buffer is full
    input logic flush,
    input logic enqueue,
    input logic dequeue,
    output width  package_out,
    input width  package_in
);


/*
* If not valid then output '0
* If a valid enqueue then output '1
*/

localparam integer ht_width = $clog2(length);
width data [length];
logic [ht_width:0] tail;
logic [ht_width:0] head;

assign full = (head[ht_width] != tail[ht_width] && head[ht_width-1:0] == tail[ht_width-1:0]);
assign empty = (head == tail);

// made package_out combinational to allow for simultaneous enqueue and dequeue
always_comb begin
    if(empty && enqueue && dequeue) begin
        package_out = package_in;
    end else if (empty) package_out = '0;
    else package_out = data[head[ht_width-1:0]];
end

always_ff @(posedge clk) begin
    if(rst || flush) begin
        tail <= '0;
        head <= '0;
        for (integer i = 0; i < length; i++) begin
            data[i] <= '0;
        end
    end 
    else begin
        if(!dequeue && enqueue && !full) begin // queueing something
            data[tail[ht_width-1:0]] <= package_in;
            tail <= tail + 4'd1;
        end else if(!enqueue && dequeue && !empty) begin // deqeue
            head <= head + 4'd1;
        end else if(enqueue && dequeue && !empty) begin // simultanesous enqueue and dequeue
            head <= head + 4'd1;
            data[tail[ht_width-1:0]] <= package_in;
            tail <= tail + 4'd1;
        end else begin
            tail <= tail;
            head <= head;
        end
    end
end
   
endmodule : instruction_queue


