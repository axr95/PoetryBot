import argparse
import re
import logging
from numpy import array
import numpy as np
import itertools
import random
import time
import os
from difflib import SequenceMatcher
from collections import deque
from keras.callbacks import LambdaCallback
from keras.models import Sequential
from keras.layers.core import Dense, Activation, Dropout
from keras.layers.recurrent import LSTM, SimpleRNN
from keras.layers import Embedding
from keras.optimizers import RMSprop
from keras import backend as K
from keras.utils import to_categorical

ap = argparse.ArgumentParser(description='Takes source files, computes a word2vec model for it, and then trains an LSTM based on the same sources that tries to predict the next word based on the last few words.')
ap.add_argument('file', help='input file')
ap.add_argument('--batch_size', type=int, default=256, help='batch size for training the NN')
ap.add_argument('--hidden_dim', type=int, default=100, help='dimension of hidden layers in the NN')
ap.add_argument('--vec_size', type=int, default=200, help='dimension of the generated word2vec vectors')
ap.add_argument('--word_lookback', type=int, default=5, help='how many words back the NN is feeded, before having to make a decision')
ap.add_argument('-e', '--epochs', type=int, default=100, help='number of epochs in training the NN')
ap.add_argument('--stateful', action='store_true', help='makes a stateful LSTM (currently ignored)')
ap.add_argument('-v', '--verbosity', type=int, default=1, help='Sets verbosity of keras while training. Accepted values: 0 - no output, 1 - one line per batch, 2 - one line per epoch')
ap.add_argument('--valid_split', type=float, default=0.5, help='ratio of how much of the data is used as validation set while training')
ap.add_argument('--predict_len', type=int, default=50, help='length of predicted sentences (in words) after each epoch')
ap.add_argument('--predict_count', type=int, default=1, help='how many different sentences should be predicted after each epoch')
ap.add_argument('-d', '--dropout', type=float, default=0.2, help="sets dropout for lstm layers")
#ap.add_argument('-o', '--output', type=string, help="destination folder of output files")

args = ap.parse_args()

BATCH_SIZE = args.batch_size
HIDDEN_DIM = args.hidden_dim
VEC_SIZE = args.vec_size
WORD_LOOKBACK = args.word_lookback
EPOCHS = args.epochs
STATEFUL = False #args.stateful
PRED_COUNT = args.predict_count
PRED_LEN = args.predict_len
DROPOUT = args.dropout


logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

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

def printIterable(iterable):
    for x in iterable:
        print(x)
    

wordCount = 0
dictSize = 1
dict = {"\n": 0}
dictIndex = ["\n"]

with open(args.file, "r", encoding="utf8") as fo:
    wIter = wordIterator(fo)
    for w in wIter:
        wordCount = wordCount + 1
        if not w in dict:
            dict[w] = dictSize
            dictIndex.append(w)
            dictSize = dictSize + 1

def getWordFromIndex(index):
    return dictIndex[index]
    #for w in dict:
    #    if dict[w] == index:
    #        return w

print (args)
print ("dictSize:", dictSize)
print ("wordCount:", wordCount)

x = np.zeros((wordCount - WORD_LOOKBACK, WORD_LOOKBACK), dtype=np.uint32)
y = np.zeros((wordCount - WORD_LOOKBACK), dtype=np.uint32)

with open(args.file, "r", encoding="utf8") as fo:
    wIter = wordIterator(fo)
    vMap  = map(lambda w: dict[w], wIter)
    sIter = sequenceIterator(vMap, WORD_LOOKBACK)
    
    for i, (hist, target) in enumerate(sIter):
        x[i,:] = hist
        y[i] = target

rest = (wordCount - WORD_LOOKBACK) % BATCH_SIZE
if rest > 0:
    x = x[range(wordCount - WORD_LOOKBACK - rest),:]
    y = y[range(wordCount - WORD_LOOKBACK - rest)]
   
rest = PRED_COUNT % BATCH_SIZE
if rest > 0:
    PRED_COUNT += BATCH_SIZE - rest
    print ("pred_count should be multiple of batch size (%i): changed from %i to %i" % (BATCH_SIZE, PRED_COUNT - BATCH_SIZE + rest, PRED_COUNT))
del rest

PRED_BATCH_COUNT = PRED_COUNT // BATCH_SIZE

# set up copy checker
seqMatcher = SequenceMatcher(a=y)

y = to_categorical(y)

# define model
model = Sequential()
model.add(Embedding(dictSize, VEC_SIZE, input_length=WORD_LOOKBACK, batch_size=BATCH_SIZE))
model.add(LSTM(HIDDEN_DIM, return_sequences=True, dropout=DROPOUT, stateful=True))
model.add(LSTM(HIDDEN_DIM, dropout=DROPOUT, stateful=True))
model.add(Dense(HIDDEN_DIM, activation='relu'))
model.add(Dense(dictSize, activation='softmax'))

# compile model
model.compile(loss='categorical_crossentropy', optimizer='adam', metrics=['accuracy'])


# https://github.com/keras-team/keras/blob/master/examples/lstm_text_generation.py
def on_epoch_end(epoch, logs):
    global x, y, seqMatcher, timestamp
    # Function invoked at end of each epoch. Prints generated text.
    print()
    print('----- Generating text after Epoch %d, which took %d seconds for training' % (epoch + 1, time.time() - timestamp))
    timestamp = time.time()
    
    x_pred = np.zeros((PRED_COUNT, WORD_LOOKBACK + PRED_LEN), dtype=np.uint32)
    x_pred[:,0:WORD_LOOKBACK] = np.copy(x[np.random.choice(x.shape[0], size=PRED_COUNT, replace=False),:])

    
    for j in range(PRED_BATCH_COUNT):
        model.reset_states()
        for i in range(PRED_LEN):
            x_pred[(j*BATCH_SIZE):((j+1)*BATCH_SIZE), i+WORD_LOOKBACK] = model.predict_classes(x_pred[(j*BATCH_SIZE):((j+1)*BATCH_SIZE), i:(i+WORD_LOOKBACK)])
    
    model.reset_states()
    
    print ('----- Generated %i texts in %i seconds.' % (PRED_COUNT, time.time() - timestamp))
    timestamp = time.time()
    
    copycounts = []
    for i in range(PRED_COUNT):
        seqMatcher.set_seq2(x_pred[i,:])
        (_, j, k) = seqMatcher.find_longest_match(0, len(y), WORD_LOOKBACK, PRED_LEN+WORD_LOOKBACK)
        copycounts.append((i,j,k))
    
    copycounts.sort(key=lambda tup: tup[2])
    
    (idx, _, cnt) = random.choice(copycounts)
    print (" ".join(map(getWordFromIndex, x_pred[idx,0:WORD_LOOKBACK])), "===>")
    print (" ".join(map(getWordFromIndex, x_pred[idx,WORD_LOOKBACK:(WORD_LOOKBACK+PRED_LEN)])))
    print ("----- End of sample with longest copied sequence:", cnt)
    print ("----- 75%% quantil of longest copied sequence: %d (computed in %d seconds)" % (copycounts[int(PRED_COUNT * 0.75)][2], time.time() - timestamp))
    timestamp = time.time()

print_callback = LambdaCallback(on_epoch_end=on_epoch_end)

print("begin train")
timestamp = time.time()

model.fit(x, y,
          batch_size=BATCH_SIZE,
          epochs=EPOCHS,
          callbacks=[print_callback],
		  shuffle=False,
		  #validation_split = args.valid_split,
		  verbose=args.verbosity)

          
model.summary()