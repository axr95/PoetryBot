@echo off
set batch_size=32
set hidden_dim=1200
set vec_size=300
set word_lookback=2
set epochs=600
set verbosity=2
set predict_len=50
set predict_count=500
set dropout=0.3

set source="source/imagist.txt"
set output="output/imagist_long"

python train.py start --batch_size %batch_size% --hidden_dim %hidden_dim% --vec_size %vec_size% --word_lookback %word_lookback% -e %epochs% -v %verbosity% --predict_len %predict_len% --predict_count %predict_count% --dropout %dropout% -o %output% %source%

shutdown -s -f -t 60

pause

shutdown -a