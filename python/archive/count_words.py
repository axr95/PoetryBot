import argparse
import re
import statistics

ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()

counts = {}

def addword(word):
    counts[word] = counts.get(word, 0) + 1
    
splitter = re.compile("[\w']+|[^\w\s]+")

with open(args.file, "r") as fo:
    for line in fo:
        words = splitter.findall(line)
        for word in words:
            if not word.isdigit():
                addword(word.lower())
        addword("\n")

i = 0
j = 0
sum = 0
med = statistics.median_high([counts[k] for k in counts])
for k in sorted(counts, key=counts.get): 
    if counts[k] >= med:
        print (k, counts[k]) 
        j += 1
        i += 1
    elif counts[k] > 1:
        i += 1
    sum += counts[k]
print ("count :", len(counts))
print (">1    :", i)
print ("sum   :", sum)
print ("median:", med)
print (">med  :", j)
