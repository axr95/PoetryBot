library("rjson")


source <- "../python/output/schachnovelle"


args <- fromJSON(file=paste(source,"args.json",sep="/"))
stats <- read.csv(file=paste(source,"stats.csv",sep="/"), header=TRUE, sep=",")

plot(stats$acc, type="l", col="green", ylim=c(0, 1), xlab="epoch", ylab="")
lines(stats$linebreaks, col="red")
lines(stats$copyblock_median / args$predict_len, col="blue")
lines(stats$copyblock_q25 / args$predict_len, col="lightblue", lty=3)
lines(stats$copyblock_q75 / args$predict_len, col="lightblue", lty=3)
legend("topleft", legend=c("Accuracy", "Percentage of Linebreaks", 
       "Median of largest copied block", "25%/75% quantils of largest copied block"),
       lty=c(1, 1, 1, 3), col=c("green", "red", "blue", "lightblue"))
