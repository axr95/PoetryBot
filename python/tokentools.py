import re
import itertools
from collections import deque


splitter = re.compile(r"[\w']+|[^\w\s+]")
#splitter = re.compile(".")


# Patterns and replacement functions to beautify the poems
# --------------------------------------------------------
bad_space = re.compile(r' ([.,:;!?€%\)\]\}])|([#§@\(\[\{\n]) ')
first_letter = re.compile(r"^\W*\w", re.MULTILINE)

def __repl_any_match(match):
    if match.group(1) is None:
        return match.group(2)
    else:
        return match.group(1)

def __repl_upper(match):
    return match.group(0).upper()

beautify_chain = [
    (bad_space, __repl_any_match),
    (first_letter, __repl_upper) ]

# --------------------------------------------------------


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
    # sorting by occurrence, then alphabetically for same results for same sources
    dict = { key: rank for rank, key in enumerate(sorted(dict, key=lambda x: (dict.get(x),x), reverse=True), 1) }
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

def renderText(tokens, dictIndex, startlen=0):
    if startlen < 0:
        startlen = -(len(tokens) + startlen)
    text = " ".join([dictIndex[x] for x in tokens[startlen:]])
    if startlen > 0:
        start = " ".join([dictIndex[x] for x in tokens[:startlen]])
        text = " ".join([start, "===>", text])
    for regex, repl in beautify_chain:
        text = regex.sub(repl, text)
    return text

def saveDictIndex(dictIndex, filename, encoding="utf8"):
    with open(filename, "w", encoding=encoding) as fo:
        for w in dictIndex:
            fo.write(w)
            fo.write("\n")

def loadDictFromFile(filename, encoding="utf8"):
    dictIndex = ["\n"]
    dict = { "\n": 0 }
    
    with open(filename, "r", encoding=encoding) as fo:
        next(fo)
        next(fo)
        i = 1
        for line in fo:
            dictIndex.append(line[:-1])
            dict[line[:-1]] = i
            i = i + 1
    return (dictIndex, dict)
            
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
    (dictIndex, dict) = loadDictFromFile("output/test_26/vocabulary.txt")
    saveDictIndex(dictIndex, "output/test_26/vocabulary2.txt")
    