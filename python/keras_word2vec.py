from gensim.models import word2vec
import argparse
import re
import logging
import numpy as np
import itertools
import random
from collections import deque
from keras.callbacks import LambdaCallback
from keras.models import Sequential
from keras.layers.core import Dense, Activation, Dropout
from keras.layers.recurrent import LSTM, SimpleRNN
from keras.layers.wrappers import TimeDistributed
from keras import backend as K


ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()


logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

BATCH_SIZE = 512
HIDDEN_DIM = 300
#SEQ_LENGTH = 40
VEC_SIZE = 200
WORD_LOOKBACK = 5
EPOCHS = 100
STATEFUL = False

ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()

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
def mapHelper(line):
    global wordCount
    res = splitter.findall(line.lower())
    res.extend("\n")
    wordCount += len(res)
    return res

with open(args.file, "r") as fo:
    sentences = list(map(mapHelper, fo))

wvmodel = word2vec.Word2Vec(sentences, size=VEC_SIZE, min_count=1)

del mapHelper
del sentences

x = np.zeros((wordCount - WORD_LOOKBACK, WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)
y = np.zeros((wordCount - WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)

with open(args.file, "r") as fo:
    wIter = wordIterator(fo)
    vMap  = map(lambda w: wvmodel.wv.get_vector(w), wIter)
    sIter = sequenceIterator(vMap, WORD_LOOKBACK)
    
    for i, (hist, target) in enumerate(sIter):
        x[i,:,:] = hist
        y[i,:] = target

#print(wvmodel.wv.similar_by_vector(random.choice(y)))

if STATEFUL:
    rest = (wordCount - WORD_LOOKBACK) % BATCH_SIZE
    if rest > 0:
        x = x[range(wordCount - WORD_LOOKBACK - rest),:,:]
        y = y[range(wordCount - WORD_LOOKBACK - rest),:]


print("setup model")

def vector_similarity(y_true, y_pred):
    y_true = K.l2_normalize(y_true, axis=-1)
    y_pred = K.l2_normalize(y_pred, axis=-1)
    res = -K.sum(y_true * y_pred, axis=-1)
    #return res
    return (1 - res**2)

#'''
model = Sequential()
if STATEFUL:
    model.add(LSTM(HIDDEN_DIM, batch_input_shape=(BATCH_SIZE, WORD_LOOKBACK, VEC_SIZE), activation=None, stateful=STATEFUL))
else:
    model.add(LSTM(HIDDEN_DIM, input_shape=(WORD_LOOKBACK, VEC_SIZE), activation=None))
#model.add(Dense(HIDDEN_DIM, input_shape=(WORD_LOOKBACK, VEC_SIZE)))
model.add(Dense(HIDDEN_DIM))
model.add(Dense(HIDDEN_DIM))
model.add(Dense(HIDDEN_DIM))
model.add(Dense(HIDDEN_DIM))
model.add(Dense(VEC_SIZE))
model.compile(loss=vector_similarity, optimizer="rmsprop")

#'''
# https://github.com/keras-team/keras/blob/master/examples/lstm_text_generation.py
def on_epoch_end(epoch, logs):
    global x, y
    # Function invoked at end of each epoch. Prints generated text.
    print()
    print('----- Generating text after Epoch: %d' % epoch)
	
    x_pred = np.zeros((BATCH_SIZE, WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)
    x_pred[0] = random.choice(x)
    
    sentence = list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], x_pred[0,:,:]))
    
    sentence += ["===>"]
    
    for i in range(31):
        #predv = model.predict(x_pred, verbose=0)
        predv = model.predict_on_batch(x_pred)
        predword = wvmodel.wv.similar_by_vector(predv[i])[0][0]
        #print (list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], x_pred[0,:,:])), " ===> ", list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], predv[0:10])))
        sentence.append(predword)
        for j in range(WORD_LOOKBACK - 1):
            x_pred[i+1, j, :] = x_pred[i, j + 1, :]
        x_pred[i+1, WORD_LOOKBACK - 1, :] = wvmodel.wv.get_vector(predword)
    
    print(" ".join(sentence))
    print()

print_callback = LambdaCallback(on_epoch_end=on_epoch_end)

print("begin train")
model.fit(x, y,
          batch_size=BATCH_SIZE,
          epochs=EPOCHS,
          callbacks=[print_callback],
		  shuffle=True,
		  validation_split = 0.5,
		  verbose=2)
          
model.summary()
#'''