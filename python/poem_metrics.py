from abc import ABC, abstractmethod
from difflib import SequenceMatcher
import tokentools

class PoemMetric(ABC):
    # Lookback has to be set accordingly from other scripts before using the metrics
    lookback = 5
    
    def __init__(self, basetext):
        self.basetext = basetext
    
    @abstractmethod
    def compute(self, poem):
        pass


class LongestCopyBlock(PoemMetric):
    
    def __init__(self, basetext):
        self.basetext = basetext
        self.seqMatcher = SequenceMatcher(a=basetext)
    
    def compute(self, poem):
        (_, _, i) = compute_details(self, poem)
        return i
        
    def compute_details(self, poem):
        self.seqMatcher.set_seq2(poem)
        return self.seqMatcher.find_longest_match(0, len(self.basetext), PoemMetric.lookback, len(poem))
        
class LongestCopyBlockNormalized(LongestCopyBlock):
    def compute(self, poem):
        return LongestCopyBlock.compute(self, poem) / (len(poem) - PoemMetric.lookback)
        
class LongestRepeat(PoemMetric):
    def __init__(self, basetext):
        self.allowedRepeats = [0]
        
    def compute(self, poem):
        n = 1
        max = 1
        last = poem[PoemMetric.lookback - 1]
        for x in poem[lookback:]:
            if last == x and x not in self.allowedRepeats:
                n = n + 1
                if n > max:
                    n = max
            else:
                last = x
                n = 1
        return max
        
class CountOfDistinctWords(PoemMetric):
    def __init__(self, basetext):
        pass
        
    def compute(self, poem):
        return len(set(poem))