import argparse
import logging
import numpy as np
import random
import time
import os
import json
import vlq
import tokentools
import gzip
import signal
from difflib import SequenceMatcher
from keras.callbacks import LambdaCallback
from keras.models import Sequential, load_model
from keras.layers.core import Dense, Activation, Dropout
from keras.layers.recurrent import LSTM, SimpleRNN
from keras.layers import Embedding
from keras.optimizers import RMSprop
from keras import backend as K
from keras.utils import to_categorical

parser = argparse.ArgumentParser(description='Takes source files, computes a vector-based word model for it, and then trains an LSTM based on the same sources that tries to predict the next word based on the last few words.')

subparsers = parser.add_subparsers()

parser_start = subparsers.add_parser('start', help='This command is used for starting a new learning process with the given arguments')
parser_start.add_argument('file', help='input file')
parser_start.add_argument('-e', '--epochs', type=int, default=100, help='number of epochs in training the NN')
parser_start.add_argument('--batch_size', type=int, default=256, help='batch size for training the NN')
parser_start.add_argument('--hidden_dim', type=int, default=100, help='dimension of hidden layers in the NN')
parser_start.add_argument('--vec_size', type=int, default=200, help='dimension of the generated word vectors')
parser_start.add_argument('--word_lookback', type=int, default=5, help='how many words back the NN is feeded, before having to make a decision')
parser_start.add_argument('-v', '--verbosity', type=int, default=1, help='Sets verbosity of keras while training. Accepted values: 0 - no output, 1 - one line per batch, 2 - one line per epoch')
parser_start.add_argument('--predict_len', type=int, default=50, help='length of predicted sentences (in words) after each epoch')
parser_start.add_argument('--predict_count', type=int, default=1, help='how many different sentences should be predicted after each epoch')
parser_start.add_argument('-d', '--dropout', type=float, default=0.4, help="sets dropout for lstm layers")
parser_start.add_argument('-o', '--output', help="destination folder of output files")

parser_continue = subparsers.add_parser('continue', help='This command is used to continue a learning process that was finished or aborted earlier, by specifying its output folder')
parser_continue.add_argument('folder', help='output folder of the run to be continued')
parser_continue.add_argument('-e', '--epochs', type=int, default=100, help='epochs to add to the existing epochs')

args = parser.parse_args()
argsdict = vars(args)

epochBase = 0

# load args if continue mode
if hasattr(args, 'folder'):
    with open(os.path.join(args.folder, "args.json"), "r", encoding="utf8") as fo:
        loadedArgs = json.load(fo)
    
    with open(os.path.join(args.folder, "stats.csv"), "r", encoding="utf8") as fo:
        for line in fo:
            pass
    # get correct number of done epochs from stats
    line = line[:line.find(",")]
    if (line == "epoch"):
        epochBase = 0
    else:
        epochBase = int(line)
    
    loadedArgs["epochs"] = epochBase + args.epochs
    loadedArgs["output"] = args.folder
    
    argsdict.update(loadedArgs)

BATCH_SIZE = args.batch_size
HIDDEN_DIM = args.hidden_dim
VEC_SIZE = args.vec_size
WORD_LOOKBACK = args.word_lookback
EPOCHS = args.epochs
PRED_COUNT = args.predict_count
PRED_LEN = args.predict_len
DROPOUT = args.dropout
OUTPUT_PATH = args.output

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.ERROR)

counts = tokentools.countWords(args.file)
dict = tokentools.getDictFromWordCounts(counts)
wordCount = sum(counts.values())
del counts

dictIndex = tokentools.getDictIndex(dict)
dictSize = len(dict)

print (args)

# tokenizing
(x,y) = tokentools.getTrainingData(args.file, WORD_LOOKBACK, dict=dict, wordCount=wordCount)

def getWordFromIndex(index):
    return dictIndex[index]
    
# shortening length to a multiple of BATCH_SIZE
rest = (wordCount - WORD_LOOKBACK) % BATCH_SIZE
if rest > 0:
    x = x[range(wordCount - WORD_LOOKBACK - rest),:]
    y = y[range(wordCount - WORD_LOOKBACK - rest)]

rest = PRED_COUNT % BATCH_SIZE
if rest > 0:
    PRED_COUNT += BATCH_SIZE - rest
    args.pred_count = PRED_COUNT
    print ("pred_count should be multiple of batch size (%i): changed from %i to %i" % (BATCH_SIZE, PRED_COUNT - BATCH_SIZE + rest, PRED_COUNT))
del rest

PRED_BATCH_COUNT = PRED_COUNT // BATCH_SIZE

# set up copy checker
seqMatcher = SequenceMatcher(a=y)

y = to_categorical(y)

dictSize = np.max(x) + 1

def defineModel():
    model = Sequential()
    model.add(Embedding(dictSize, VEC_SIZE, input_length=WORD_LOOKBACK, batch_size=BATCH_SIZE))
    model.add(LSTM(HIDDEN_DIM, return_sequences=True, dropout=DROPOUT, stateful=True))
    model.add(LSTM(HIDDEN_DIM, dropout=DROPOUT, stateful=True))
    model.add(Dense(HIDDEN_DIM, activation='relu'))
    model.add(Dense(dictSize, activation='softmax'))

    # compile model
    model.compile(loss='categorical_crossentropy', optimizer='adam', metrics=['accuracy'])
    return model

if not hasattr(args, 'folder'):
    if os.path.exists(OUTPUT_PATH):
        num = 2
        while os.path.exists("%s_%d" % (OUTPUT_PATH, num)):
            num += 1
        OUTPUT_PATH = "%s_%d" % (OUTPUT_PATH, num)
        del num

    os.makedirs(OUTPUT_PATH)

    ###Maybe has to come back to make it loadable, but the json should do this good enough
    #with open(os.path.join(OUTPUT_PATH, "args.txt"), "wb") as fo:
        #pickle.dump(args, fo, 0)

        
    with open(os.path.join(OUTPUT_PATH, "stats.csv"), "a", encoding="utf8") as fo:
        fo.write("epoch,acc,loss,linebreaks,copyblock_q25,copyblock_median,copyblock_q75")
        fo.write("\n")
    
    tokentools.saveDictIndex(dictIndex, os.path.join(OUTPUT_PATH, "vocabulary.txt"))
    
    # define model
    model = defineModel()
else:
    # load model
    if os.path.exists(os.path.join(args.folder, "model.h5")):
        model = load_model(os.path.join(args.folder, "model.h5"))
    else:
        model = defineModel()
    del args.folder


with open(os.path.join(OUTPUT_PATH, "args.json"), "w") as fo:
    fo.write(json.dumps(vars(args), indent=4))
    
# https://github.com/keras-team/keras/blob/master/examples/lstm_text_generation.py
def on_epoch_end(epoch, logs):
    global x, y, seqMatcher, timestamp
    epoch = epochBase + epoch
    
    interrupted = False
    def interruptHandler(signal, frame):
        nonlocal interrupted
        print ("caught interrupt - exiting program after end-of-epoch updating")
        interrupted = True
    prevHandler = signal.signal(signal.SIGINT, interruptHandler)
    
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
    
    
    # compute similarity to sources
    copyblocks = []
    for i in range(PRED_COUNT):
        seqMatcher.set_seq2(x_pred[i,:])
        (_, j, k) = seqMatcher.find_longest_match(0, len(y), WORD_LOOKBACK, PRED_LEN+WORD_LOOKBACK)
        copyblocks.append((i,j,k))

    
    copyblocks.sort(key=lambda tup: tup[2])
    
    (idx, _, cnt) = random.choice(copyblocks)
    print (" ".join(map(getWordFromIndex, x_pred[idx,0:WORD_LOOKBACK])), "===>")
    print (" ".join(map(getWordFromIndex, x_pred[idx,WORD_LOOKBACK:(WORD_LOOKBACK+PRED_LEN)])))
    print ("----- End of sample with longest copied sequence:", cnt)
    print ("----- 75%% quantil of longest copied sequence: %d (computed in %d seconds)" % (copyblocks[int(PRED_COUNT * 0.75)][2], time.time() - timestamp))
    
    statsToSave = [
            epoch,
            logs["acc"],
            logs["loss"],
            1 - np.count_nonzero(x_pred) / x_pred.size,
            copyblocks[int(PRED_COUNT * 0.25)][2],
            copyblocks[int(PRED_COUNT * 0.50)][2],
            copyblocks[int(PRED_COUNT * 0.75)][2],
            ]
    
    
    with open(os.path.join(OUTPUT_PATH, "stats.csv"), "a", encoding="utf8") as fo:
        fo.write(",".join(map(str, statsToSave)))
        fo.write("\n")
    
    with open(os.path.join(OUTPUT_PATH, "poems.txt"), "a", encoding="utf8") as fo:
        fo.write("Epoch %d ----------------------------\n" % (epoch + 1))
        for i in range(PRED_COUNT):
            fo.write("%d ---------------------------------\n" % i)
            fo.write(" ".join(map(getWordFromIndex, x_pred[i,0:WORD_LOOKBACK])))
            fo.write(" ===>\n")
            fo.write(" ".join(map(getWordFromIndex, x_pred[i,WORD_LOOKBACK:(WORD_LOOKBACK+PRED_LEN)])))
            fo.write("\n")
     
    # maybe it is easier for further processing to save the file in binary. Also much smaller with vlq and gzip
    with gzip.open(os.path.join(OUTPUT_PATH, "poems_encoded.vlq.gz"), "ab") as fo:
        vlq.save(x_pred.flat, fo)
        
    model.save(os.path.join(OUTPUT_PATH, "model.h5"))
    
    
    signal.signal(signal.SIGINT, prevHandler)
    if (interrupted):
        print ("Interrupted - exiting...")
        exit(0)
    
    timestamp = time.time()

print_callback = LambdaCallback(on_epoch_end=on_epoch_end)

print("begin train")
timestamp = time.time()

model.fit(x, y,
          batch_size=BATCH_SIZE,
          epochs=EPOCHS,
          callbacks=[print_callback],
		  shuffle=False,
		  verbose=args.verbosity)

          
model.summary()
