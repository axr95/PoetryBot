
def load(fo):
    res = []
    b = fo.read(1)
    while (b != b''):
        b = int.from_bytes(b, 'little')
        x = b & 0x7F
        sh = 7
        while (b & 0x80 > 0):
            b = int.from_bytes(fo.read(1), 'little')
            x = x | ((b & 0x7F) << sh)
            sh = sh + 7
        res.append(x)
        b = fo.read(1)
    return res

def save(data, fo):
    for x in data:
        while x > 0x7F:
            fo.write(bytes([(0x7F & x) | 0x80]))
            x = x >> 7
        fo.write(bytes([x]))
        

if __name__ == '__main__':
    x = [0, 1, 127, 128, 2048, 34564, 25615486, 5154646126351]
    
    with open('test', 'wb') as fo:
        save(x, fo)
    
    with open('test', 'rb') as fo:
        y = load(fo)
        
    print (x == y, x, y)