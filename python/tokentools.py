import re
import itertools
from collections import deque


splitter = re.compile("[\w']+|[^\w\s+]")

def wordIterator(lineiterable):
    for line in lineiterable:
        words = splitter.findall(line.lower())
        for w in words:
            yield w
        yield "\n"

def sequenceIterator(baseiterable, lookback):
    history = deque(itertools.islice(baseiterable, lookback))
    for x in baseiterable:
        yield (list(history), x)
        history.popleft()
        history.append(x)

def countWords(filename, encoding="utf8"):
    dict = { "\n": 0 }

    with open(filename, "r", encoding=encoding) as fo:
        wIter = wordIterator(fo)
        for w in wIter:
            if not w in dict:
                dict[w] = 0
            dict[w] = dict[w] + 1
    return dict

def getDictFromWordCounts(wordcounts):
    dict = wordcounts.copy()
    del dict["\n"]
    
    # getting dict by rank: https://stackoverflow.com/questions/30282600/python-ranking-dictionary-return-rank
    dict = { key: rank for rank, key in enumerate(sorted(dict, key=dict.get, reverse=True), 1) }
    dict["\n"] = 0
    return dict

def getDict(filename, encoding="utf8"):
    dict = countWords(filename, encoding)
    return getDictFromWordCounts(dict)
    
def getDictIndex(dict):
    dictIndex = [None] * len(dict)
    for w in dict:
        dictIndex[dict[w]] = w
    return dictIndex

def getTokens(dict, filename, encoding="utf8"):
    with open(filename, "r", encoding=encoding) as fo:
        wIter = wordIterator(fo)
        return list(map(lambda w: dict[w], wIter))
#21694, 4641
try:
    import numpy as np
    
    def getTrainingData(filename, wordLookback, dict=None, wordCount=None, encoding="utf8"):
        if not (dict and wordCount):
            dict = countWords(filename, encoding)
            wordCount = sum(dict.values())
            
            dict = getDictFromWordCounts(dict)
        
        
        x = np.zeros((wordCount - wordLookback, wordLookback), dtype=np.uint32)
        y = np.zeros((wordCount - wordLookback), dtype=np.uint32)
        
        with open(filename, "r", encoding=encoding) as fo:
            wIter = wordIterator(fo)
            vMap  = map(lambda w: dict[w], wIter)
            sIter = sequenceIterator(vMap, wordLookback)
            
            for i, (hist, target) in enumerate(sIter):
                x[i,:] = hist
                y[i] = target
            
        return (x, y)
    
except ImportError:
    pass

if __name__ == "__main__":
    counts = countWords("source/schachnovelle.txt")
    wordCount = sum(counts.values())
    dict = getDictFromWordCounts(counts)
    
    print (wordCount)
    vMap = getTokens(dict, "source/schachnovelle.txt")
    sIter = sequenceIterator(vMap, 5)
        
    print(len(list(sIter)))
    
    
    