from gensim.models import word2vec
from sklearn.manifold import TSNE
from sklearn.datasets import fetch_20newsgroups
import argparse
import re
import logging
import matplotlib.pyplot as plt

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)
 

ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()

splitter = re.compile("[\w']+|[^\w\s]+")

with open(args.file, "r") as fo:
    sentences = list(map(lambda line : splitter.findall(line.lower()), fo))

wvmodel = word2vec.Word2Vec(sentences, size=200, min_count=50, window=10, sample=1e-3)

print (wvmodel.wv.most_similar([',']))


#tsne
X = wvmodel[wvmodel.wv.vocab]

tsne = TSNE(n_components=2)
X_tsne = tsne.fit_transform(X)

plt.scatter(X_tsne[:, 0], X_tsne[:, 1])
for i, txt in enumerate(wvmodel.wv.vocab):
    plt.annotate(txt, (X_tsne[i,0], X_tsne[i,1]))

plt.show()