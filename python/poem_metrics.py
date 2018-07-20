from abc import ABC, abstractmethod
from difflib import SequenceMatcher

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
        self.seqMatcher.set_seq2(poem)
        (_, _, i) = self.seqMatcher.find_longest_match(0, len(self.basetext), PoemMetric.lookback, len(poem))
        return i
        
class LongestCopyBlockNormalized(LongestCopyBlock):
    def compute(self, poem):
        return LongestCopyBlock.compute(self, poem) / (len(poem) - PoemMetric.lookback)