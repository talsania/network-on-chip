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
            plt.imshow(image_data) 
            plt.title("NoC Received RGB Image")
            plt.axis('off')
            plt.show()

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    listen_to_noc()
