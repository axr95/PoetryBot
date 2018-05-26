from gensim.models import word2vec
import argparse
import re
import logging
import numpy as np
import itertools
import random
import pyttsx3
from collections import deque
from keras.callbacks import LambdaCallback
from keras.models import Sequential
from keras.layers.core import Dense, Activation, Dropout
from keras.layers.recurrent import LSTM, SimpleRNN
from keras.optimizers import RMSprop
from keras import backend as K


ap = argparse.ArgumentParser(description='Takes source files, computes a word2vec model for it, and then trains an LSTM based on the same sources that tries to predict the next word based on the last few words.')
ap.add_argument('file', help='input file')
ap.add_argument('--batch_size', metavar='batch-size', type=int, default=256, help='batch size for training the NN')
ap.add_argument('--hidden_dim', metavar='hidden-dim', type=int, default=500, help='dimension of hidden layers in the NN')
ap.add_argument('--vec_size', metavar='vec-size', type=int, default=200, help='dimension of the generated word2vec vectors')
ap.add_argument('--word_lookback', metavar='word-lookback', type=int, default=5, help='how many words back the NN is feeded, before having to make a decision')
ap.add_argument('--epochs', type=int, default=100, help='number of epochs in training the NN')
ap.add_argument('--stateful', action='store_true', help='makes a stateful LSTM (experimental)')
ap.add_argument('-v', '--verbosity', type=int, default=1, help='Sets verbosity of keras while training. Accepted values: 0 - no output, 1 - one line per batch, 2 - one line per epoch')
ap.add_argument('--valid_split', metavar='valid-split', type=float, default=0.5, help='ratio of how much of the data is used as validation set while training')


args = ap.parse_args()

BATCH_SIZE = args.batch_size
HIDDEN_DIM = args.hidden_dim
#SEQ_LENGTH = 40
VEC_SIZE = args.vec_size
WORD_LOOKBACK = args.word_lookback
EPOCHS = args.epochs
STATEFUL = args.stateful

print(args)

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

splitter = re.compile("[\w']+|[^\w\s]+")


speaker = pyttsx3.init()

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

with open(args.file, "r", encoding="utf8") as fo:
    sentences = list(map(mapHelper, fo))

wvmodel = word2vec.Word2Vec(sentences, size=VEC_SIZE, min_count=1)

del mapHelper
del sentences

x = np.zeros((wordCount - WORD_LOOKBACK, WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)
y = np.zeros((wordCount - WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)

with open(args.file, "r", encoding="utf8") as fo:
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
    #return (1 - res ** 2)
    return (-res)

#'''
model = Sequential()
if STATEFUL:
    model.add(LSTM(HIDDEN_DIM, batch_input_shape=(BATCH_SIZE, WORD_LOOKBACK, VEC_SIZE), activation=None, stateful=STATEFUL))
else:
    model.add(LSTM(HIDDEN_DIM, input_shape=(WORD_LOOKBACK, VEC_SIZE), activation=None))
#model.add(Dense(HIDDEN_DIM, input_shape=(WORD_LOOKBACK, VEC_SIZE)))
model.add(Dense(HIDDEN_DIM))
#model.add(Dense(HIDDEN_DIM))
#model.add(Dense(HIDDEN_DIM))
#model.add(Dense(HIDDEN_DIM))
model.add(Dense(VEC_SIZE))

optimizer = RMSprop(lr=0.001)
model.compile(loss=vector_similarity, optimizer=optimizer)

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
    
    for i in range(min(BATCH_SIZE - 1, 20)):
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
    speaker.say(" ".join(sentence))
    speaker.runAndWait()

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