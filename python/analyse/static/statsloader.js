let loadedPoem;

function updateEpoch() {
    let statsRoot = $("#epochStats");
    //statsRoot.html("Loading...");
    
    // https://stackoverflow.com/questions/16237780/get-last-part-of-uri
    let urlsplit = window.location.pathname.split("/");
    let runid = urlsplit[urlsplit.length-1];
    
    $.getJSON("/data/" + runid + "/" + $("#epochChooser").val(), function(data) {
        statsRoot.html("");
        $.each(data, function(key,val) {
            if (typeof(val) === "number" && !Number.isInteger(val)) {
                val = val.toFixed(2);
            }
            statsRoot.append("<dt>"+key+"</dt><dd>"+val+"</dd>");
        });
    });
    
    updatePoem();
}

function updatePoem() {
    let poem = $("#poem");
    //poem.html("Loading...");
    
    let metricsRoot = $("#poemMetrics");
    //metricsRoot.html("Loading...");

    let runid = getRunId();
    
    $.getJSON("/data/" + runid + "/" + $("#epochChooser").val() + "/" + $("#poemChooser").val(), function(data) {
        loadedPoem = data;
        poem.html(data["poem"]);
        metricsRoot.html("");
        $.each(data["metrics"], function(key,val) {
            metricsRoot.append("<dt>"+key+"</dt><dd>"+val+"</dd>");
        });
        document.getElementById("favouriteStar").getSVGDocument().getElementById("star").setAttribute("fill", (data["favourite"] ? "orange" : "gray"));
    });
}

function offsetPoem(poemOffset = 0, epochOffset = 0) {
    function updateIfInRange(inputElement, offset) {
        let newValue = parseInt(inputElement.val(), 10) + offset;
        if (offset > 0) {
            if (parseInt(inputElement.attr("max")) < newValue) {
                return;
            }
        } else {
            if (parseInt(inputElement.attr("min")) > newValue) {
                return;
            }
        }
        inputElement.val(newValue);
    }
    if (epochOffset !== 0) {
        let epochChooser = $("#epochChooser");
        updateIfInRange(epochChooser, epochOffset);
        updateEpoch();
    }
    if (poemOffset !== 0) {
        let poemChooser = $("#poemChooser");
        updateIfInRange(poemChooser, poemOffset);
    }
    updatePoem();
    //$("#poemMetrics").get(0).scrollIntoView();
}

function toggleFavourite() {
    let runid = getRunId();
    $.post("/favourite", { "runid": runid, "epoch": $("#epochChooser").val(), "poemid": $("#poemChooser").val(), "unfavourite": loadedPoem["favourite"] }, function(data) {
        if (data["success"] === true) {
            loadedPoem["favourite"] = !loadedPoem["favourite"];
            document.getElementById("favouriteStar").getSVGDocument().getElementById("star").setAttribute("fill", (loadedPoem["favourite"] === true) ? "orange" : "gray");
        }
    }, "json");
}

function getRunId() {
    // https://stackoverflow.com/questions/16237780/get-last-part-of-uri
    let urlsplit = window.location.pathname.split("/");
    return urlsplit[urlsplit.length-1];
}

window.onload = updateEpoch;