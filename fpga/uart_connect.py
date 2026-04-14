import serial
import numpy as np
import matplotlib.pyplot as plt
import sys

# --- CONFIGURATION ---
COM_PORT = 'COM17'  
BAUD_RATE = 115200

def listen_to_noc():
    # Initialize 64x64 with 3 color channels (RGB)
    image_data = np.zeros((64, 64, 3), dtype=np.uint8)
    
    try:
        with serial.Serial(COM_PORT, BAUD_RATE, timeout=2) as ser:
            print(f"Listening on {COM_PORT}... Press the FPGA Button to start!")
            
            packets_received = 0
            expected_packets = 4096
            
            while packets_received < expected_packets:
                header = ser.read(1)
                
                if not header:
                    if packets_received == 0:
                        print(".", end="", flush=True)
                        continue
                    else:
                        print(f"\nTimeout! Stream stopped unexpectedly at {packets_received} packets.")
                        break
                    
                if header == b'\xB3':
                    # Read 7 Bytes (5 Payload + 2 Latency)
                    data = ser.read(7)
                    if len(data) == 7:
                        p4, p3, p2, p1, p0, lat_hi, lat_lo = data
                        
                        # Reconstruct 40-bit Payload
                        payload = (p4 << 32) | (p3 << 24) | (p2 << 16) | (p1 << 8) | p0
                        
                        # Extract Address (12 bits) and RGB (24 bits)
                        pixel_addr = (payload >> 24) & 0x0FFF
                        r = (payload >> 16) & 0xFF
                        g = (payload >> 8)  & 0xFF
                        b = payload & 0xFF
                        
                        y = pixel_addr // 64
                        x = pixel_addr % 64
                        
                        if y < 64 and x < 64:
                            image_data[y, x] = [r, g, b]
                            
                        packets_received += 1
                        
                        if packets_received == 1:
                            print("\nStream started! Receiving RGB data...")
                        elif packets_received % 512 == 0:
                            print(f"Received {packets_received}/{expected_packets} packets...")

            print("\nStream Complete! Rendering Image...")
            plt.imshow(image_data) # Matplotlib handles RGB natively
            plt.title("NoC Received RGB Image")
            plt.axis('off')
            plt.show()

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    listen_to_noc()

# import serial

# # --- CONFIGURATION ---
# COM_PORT = 'COM17'  
# BAUD_RATE = 115200
# LOG_FILE = "debug_log.txt"

# def debug_stream():
#     def log(msg, end='\n'):
#         print(msg, end=end)
#         f.write(msg + end)

#     with open(LOG_FILE, "w") as f:
#         log(f"Connecting to {COM_PORT} at {BAUD_RATE} baud...")
#         try:
#             with serial.Serial(COM_PORT, BAUD_RATE, timeout=0.1) as ser:
#                 log("Press the FPGA Button NOW!")
                
#                 buffer = bytearray()
#                 no_data_count = 0
                
#                 # 1. CAPTURE PHASE
#                 while True:
#                     chunk = ser.read(1024)
#                     if chunk:
#                         buffer.extend(chunk)
#                         no_data_count = 0
#                         # Only print to console so we don't spam the log file too much during rx
#                         print(f"Received chunk... Total bytes: {len(buffer)}", end='\r')
#                     else:
#                         if len(buffer) > 0:
#                             no_data_count += 1
                        
#                         if no_data_count > 20: # roughly 2 seconds of silence
#                             print() # clear the \r line
#                             log(f"\nStream ended. Total bytes captured: {len(buffer)}")
#                             break
                
#                 if len(buffer) == 0:
#                     log("No data received. Is the COM port correct?")
#                     return
                
#                 # 2. RAW DUMP PHASE
#                 log("\n--- RAW HEX DUMP ---")
#                 # Print in chunks of 16 bytes for readability
#                 for i in range(0, len(buffer), 16):
#                     chunk_hex = " ".join([f"{b:02X}" for b in buffer[i:i+16]])
#                     log(f"{i:04X} | {chunk_hex}")
                
#                 # 3. ANALYSIS PHASE
#                 log("\n--- PACKET ANALYSIS ---")
#                 idx = 0
#                 packet_count = 0
                
#                 while idx < len(buffer):
#                     if buffer[idx] == 0xB3:  # Found Node 3 Header!
#                         if idx + 7 <= len(buffer): # RGB Packet is 7 Bytes total
#                             packet = buffer[idx:idx+7]
#                             p4, p3, p2, p1, p0, lat_hi, lat_lo = packet[1:]
                            
#                             payload = (p4 << 32) | (p3 << 24) | (p2 << 16) | (p1 << 8) | p0
#                             addr = (payload >> 24) & 0x0FFF
#                             r = (payload >> 16) & 0xFF
#                             g = (payload >> 8)  & 0xFF
#                             b = payload & 0xFF
#                             lat = (lat_hi << 8) | lat_lo
                            
#                             log(f"[{packet_count:04d}] Addr: {addr:04d} | RGB: ({r:03d},{g:03d},{b:03d}) | Latency: {lat:05d} | Raw: {packet.hex().upper()}")
#                             packet_count += 1
#                             idx += 7  # Jump ahead 7 bytes
#                         else:
#                             log(f"-> INCOMPLETE PACKET at end of buffer: {buffer[idx:].hex().upper()}")
#                             break
#                     else:
#                         log(f"-> FRAMING ERROR at byte {idx:04X}: Expected B3, got {buffer[idx]:02X}")
#                         idx += 1  # Shift by 1 byte to try and resync
                        
#                 log(f"\nSuccessfully parsed {packet_count} complete packets.")

#         except Exception as e:
#             log(f"Error: {e}")

# if __name__ == "__main__":
#     debug_stream()