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


ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()


logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

BATCH_SIZE = 128
HIDDEN_DIM = 500
#SEQ_LENGTH = 40
VEC_SIZE = 200
WORD_LOOKBACK = 20

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
	sentences = map(mapHelper, fo)
	wvmodel = word2vec.Word2Vec(sentences, size=VEC_SIZE, min_count=1)

del mapHelper

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

print("setup model")
#'''
model = Sequential()
model.add(LSTM(HIDDEN_DIM, input_shape=(WORD_LOOKBACK, VEC_SIZE)))
model.add(Dense(VEC_SIZE))
model.add(Dense(VEC_SIZE))
model.add(Dense(VEC_SIZE))
model.add(Activation('tanh'))
model.compile(loss="mean_squared_error", optimizer="rmsprop")

# https://github.com/keras-team/keras/blob/master/examples/lstm_text_generation.py
def on_epoch_end(epoch, logs):
	# Function invoked at end of each epoch. Prints generated text.
	print()
	print('----- Generating text after Epoch: %d' % epoch)
	
	x_pred = np.zeros((1, WORD_LOOKBACK, VEC_SIZE), dtype=np.float32)
	x_pred[0] = random.choice(x)
	
	sentence = list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], x_pred[0,:,:]))
	
	for i in range(20):
		predv = model.predict(x_pred, verbose=0)
		predword = wvmodel.wv.similar_by_vector(predv[0])[0][0]
		#print (list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], x_pred[0,:,:])), " ===> ", list(map(lambda vec : wvmodel.wv.similar_by_vector(vec)[0][0], predv[0:10])))
		sentence.append(predword)
		predv = wvmodel.wv.get_vector(predword)
		for j in range(WORD_LOOKBACK - 1):
			x_pred[0, j, :] = x_pred[0, j + 1, :]
		x_pred[0, WORD_LOOKBACK - 1, :] = predv
	
	print(" ".join(sentence))
	print()

print_callback = LambdaCallback(on_epoch_end=on_epoch_end)

print("begin train")
model.fit(x, y,
          batch_size=BATCH_SIZE,
          epochs=100,
		  callbacks=[print_callback])
		  
model.summary()
#'''