import argparse
import re
import logging
from numpy import array
import numpy as np
import itertools
import random
from collections import deque
from keras.callbacks import LambdaCallback
from keras.models import Sequential
from keras.layers.core import Dense, Activation, Dropout
from keras.layers.recurrent import LSTM, SimpleRNN
from keras.layers import Embedding
from keras.optimizers import RMSprop
from keras import backend as K
from keras.utils import to_categorical
from keras.preprocessing.text import Tokenizer

ap = argparse.ArgumentParser(description='Takes source files, computes a word2vec model for it, and then trains an LSTM based on the same sources that tries to predict the next word based on the last few words.')
ap.add_argument('file', help='input file')
ap.add_argument('--batch_size', type=int, default=256, help='batch size for training the NN')
ap.add_argument('--hidden_dim', type=int, default=500, help='dimension of hidden layers in the NN')
ap.add_argument('--vec_size', type=int, default=200, help='dimension of the generated word2vec vectors')
ap.add_argument('--word_lookback', type=int, default=5, help='how many words back the NN is feeded, before having to make a decision')
ap.add_argument('--epochs', type=int, default=100, help='number of epochs in training the NN')
ap.add_argument('--stateful', action='store_true', help='makes a stateful LSTM (experimental)')
ap.add_argument('-v', '--verbosity', type=int, default=1, help='Sets verbosity of keras while training. Accepted values: 0 - no output, 1 - one line per batch, 2 - one line per epoch')
ap.add_argument('--valid_split', type=float, default=0.5, help='ratio of how much of the data is used as validation set while training')

args = ap.parse_args()

BATCH_SIZE = args.batch_size
HIDDEN_DIM = args.hidden_dim
#SEQ_LENGTH = 40
VEC_SIZE = args.vec_size
WORD_LOOKBACK = args.word_lookback
EPOCHS = args.epochs
STATEFUL = args.stateful

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

splitter = re.compile("[\w']+|[^\w\s]+")

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
dictSize = 0
dict = {}

with open(args.file, "r", encoding="utf8") as fo:
    wIter = wordIterator(fo)
    for w in wIter:
        wordCount = wordCount + 1
        if not w in dict:
            dict[w] = dictSize
            dictSize = dictSize + 1

def getWordFromIndex(index):
    for w in dict:
        if dict[w] == index:
            return w

x = np.zeros((wordCount - WORD_LOOKBACK, WORD_LOOKBACK), dtype=np.int)
y = np.zeros((wordCount - WORD_LOOKBACK), dtype=np.int)

with open(args.file, "r", encoding="utf8") as fo:
    wIter = wordIterator(fo)
    vMap  = map(lambda w: dict[w], wIter)
    sIter = sequenceIterator(vMap, WORD_LOOKBACK)
    
    for i, (hist, target) in enumerate(sIter):
        x[i,:] = hist
        y[i] = target

y = to_categorical(y)
# define model
model = Sequential()
model.add(Embedding(dictSize, VEC_SIZE, input_length=WORD_LOOKBACK))
model.add(LSTM(100, return_sequences=True))
model.add(LSTM(100))
model.add(Dense(100, activation='relu'))
model.add(Dense(dictSize, activation='softmax'))

# compile model
model.compile(loss='categorical_crossentropy', optimizer='adam', metrics=['accuracy'])

#'''
# https://github.com/keras-team/keras/blob/master/examples/lstm_text_generation.py
def on_epoch_end(epoch, logs):
    global x, y
    # Function invoked at end of each epoch. Prints generated text.
    print()
    print('----- Generating text after Epoch: %d' % epoch)
	
    x_pred = np.zeros((1, WORD_LOOKBACK), dtype=np.int)
    x_pred[0,:] = np.asarray(random.choice(x), dtype=np.int)
    
    print(x_pred)
    
    sentence = list(map(getWordFromIndex, x_pred[0]))
    
    sentence += ["===>"]
    
    for i in range(min(BATCH_SIZE - 1, 20)):
        #predv = model.predict(x_pred, verbose=0)
        predv = model.predict_classes(x_pred)[0]
        predword = getWordFromIndex(predv)
        sentence.append(predword)
        for j in range(WORD_LOOKBACK - 1):
            x_pred[0,j] = x_pred[0,j + 1]
        x_pred[0,WORD_LOOKBACK - 1] = predv
    
    print(" ".join(sentence))
    print()

print_callback = LambdaCallback(on_epoch_end=on_epoch_end)

print("begin train")
model.fit(x, y,
          batch_size=BATCH_SIZE,
          epochs=EPOCHS,
          callbacks=[print_callback],
		  shuffle=not STATEFUL,
		  validation_split = args.valid_split,
		  verbose=args.verbosity)
          
model.summary()
#'''