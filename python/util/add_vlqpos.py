import argparse

import sys
import os
import errno

import json

sys.path.insert(0, "..")
import vlq
import gzip
import pandas

parser = argparse.ArgumentParser(description='Helper script that inserts __vlqpos in stats.csv file')

parser.add_argument('input', nargs='?', default='../output', help='base folder where the run output folders are stored; can also be a single file in the folder you want to process')

args = parser.parse_args()



if os.path.isfile(args.input):
    folders = [os.path.dirname(args.input)]
elif os.path.isdir(args.input):
    folders = []
    for folder in os.listdir(args.input):
        if os.path.isdir(os.path.join(args.input, folder)):
            folders.append(os.path.join(args.input, folder))
else:
    print("Given input file or folder does not exist! Terminating...")
    exit(0)

results = [0,0,0]
    
for folder in folders:
    def getFile(filename):
        folder
        return os.path.join(folder, filename)
    try:
        with open(getFile("args.json"), "r", encoding="utf8") as fo:
            runArgs = json.load(fo)
        
        if "pred_count" in runArgs:
            runArgs["predict_count"] = runArgs["pred_count"]
            del runArgs["pred_count"]
            with open(getFile("args.json"), "w", encoding="utf8") as fo:
                json.dump(runArgs, fo, indent=4)
        
        
        epochSize = (runArgs["predict_len"] + runArgs["word_lookback"]) * runArgs["predict_count"]
        
        stats = pandas.read_csv(getFile("stats.csv"))
        
        if '__vlqpos' in stats.columns:
            print('Column "__vlqpos" already exists in', getFile("stats.csv"), '! Ignoring this folder...')
            results[1] += 1 
            continue
        
        poemfile = getFile("poems_encoded.vlq.gz")
        if not os.path.isfile(poemfile):
            raise FileNotFoundError(errno.ENOENT, os.strerror(errno.ENOENT), poemfile)
            
        stats.insert(1, "__vlqpos", -1)
        
        with gzip.open(poemfile, "rb") as fo:
            epoch = 0
            pos = 0
            len = 0
            b = fo.read(1)
            while b != b'':
                if pos % epochSize == 0:
                    stats.iat[epoch, 1] = len
                    epoch += 1
                    
                b = int.from_bytes(b, 'little')
                while (b & 0x80 > 0):
                    b = int.from_bytes(fo.read(1), 'little')
                    len += 1
                
                b = fo.read(1)
                pos += 1
                len += 1
        
        stats.to_csv(getFile("stats.csv"), index=False, encoding="utf8")
        print("Folder", folder, "successfully updated!")
        results[0] += 1
        
    except FileNotFoundError as not_found:
        print("Error:", not_found.filename, "was not found! Ignoring this folder...")
        results[2] += 1 
    except Exception as e:
        print("Error while processing", folder, "--", str(e), "-- Ignoring this folder...")
        results[2] += 1
        
    sys.stdout.flush()
        
print("Processing folders complete! (%d successful / %d ignored / %d errors)" % tuple(results))