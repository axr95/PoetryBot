@echo off
set batch_size=32
set hidden_dim=100
set vec_size=200
set word_lookback=5
set epochs=100
set verbosity=2
set predict_len=50
set predict_count=100
set dropout=0.2

set source="../processing/poetrybot/data/poemsource/poetry/sword blades and poppy seeds.txt"
set output="./output/test"

python keras_classpred.py --batch_size %batch_size% --hidden_dim %hidden_dim% --vec_size %vec_size% --word_lookback %word_lookback% -e %epochs% -v %verbosity% --predict_len %predict_len% --predict_count %predict_count% --dropout %dropout% -o %output% %source%

pause