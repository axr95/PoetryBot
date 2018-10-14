
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
    
def loadrange(fo, start, end, offset=0):
    res = []
    
    if offset > 0:
        fo.seek(offset)
    
    pos = 0    
    
    b = fo.read(1)
    
    while pos < start:
        b = int.from_bytes(b, 'little')
        if b & 0x80 == 0:
            pos += 1
        b = fo.read(1)
    
    while pos < end and b != b'':
        b = int.from_bytes(b, 'little')
        x = b & 0x7F
        sh = 7
        while (b & 0x80 > 0):
            b = int.from_bytes(fo.read(1), 'little')
            x = x | ((b & 0x7F) << sh)
            sh = sh + 7
        res.append(x)
        pos += 1
        b = fo.read(1)
        
    return res

def save(data, fo):
    len = 0
    for x in data:
        while x > 0x7F:
            fo.write(bytes([(0x7F & x) | 0x80]))
            len += 1
            x = x >> 7
        fo.write(bytes([x]))
        len += 1
    return len

if __name__ == '__main__':
    x = [0, 1, 127, 128, 2048, 34564, 25615486, 5154646126351]
    
    with open('test', 'wb') as fo:
        save(x, fo)
    
    with open('test', 'rb') as fo:
        y = load(fo)
        
    print (x == y, x, y)