#Slight modifications have been made to the original repository files to adapt the functions to EvamTools.

#Code from https://github.com/StochasticBiology/hypercube-hmm .
#Commit fd53923 from 2022-11-11

#Authors of code: Stochastic Biology Group (Iain Johnston at University of Bergen) and Marcus Moen.

#Author of paper/project: Marcus T. Moen and Iain G. Johnston

#Paper: Moen, M. T., & Johnston, I. G. (2022). HyperHMM: Efficient inference of evolutionary and progressive dynamics on hypercubic transition graphs. 
#Bioinformatics (Oxford, England), btac803. Advance online publication. https://doi.org/10.1093/bioinformatics/btac803



do_HyperHMM <- function(xoriginal,
                        precursors = NA, # precursors (e.g. ancestors) -- blank for cross-sectional
                        nboot = 1, # number of boostrap resamples
                        random.walkers = 0, # run random walkers for each resample? 0 no, 1 yes
                        label = "label", # label for file I/O
                        simulate = TRUE, # actually run HyperHMM? If not, try and pull precomputed output using "label"
                        fork = FALSE # if we are running it, fork to a new process, or keep linear?
                        ){
  # get number and names of features
  L <- ncol(xoriginal)
  features <- colnames(xoriginal)
  
  
  # possible names of executable
  cmds <- c("hyperhmm.ce", "hyperhmm.exe", "hyperhmm")
  #see if any are here
  found <- FALSE
  commandname <- ""
  for(cmd in cmds) {
    commandpath <- Sys.which(cmd)
    if(nchar(commandpath) > 0) {
      commandname <- commandpath
      found <- TRUE
    }
  }
  if (found == FALSE) { message ("Couldn't find HyperHMM executable in the PATH") }
  
  
  # deal with non-binary values
  if(any(xoriginal != 0 & xoriginal != 1)) {
    message("Non-binary observations found. Interpreting all nonzero entries as presence")
    xoriginal[xoriginal != 0 & xoriginal != 1] <- 1
  }
  
  #compile into strings
  obs.sums <- rowSums(xoriginal)
  obs.rows <- apply(xoriginal, 1, paste, collapse="")
  final.rows <- obs.rows
  
  # check to see if precursor states have been provided; set cross-sectional flag accordingly
  if(!is.matrix(precursors)) { 
    message("Couldn't interpret precursors observations as matrix!")
    message("No precursor observations; assuming cross-sectional setup.")
    cross.sectional = 1
  } else {
    cross.sectional = 0
    # deal with issues in precursor set
    if(nrow(precursors) != nrow(xoriginal)) { message("Number of observations and precursors didn't match!"); return()}
    if(ncol(precursors) != ncol(xoriginal)) { message("Number of features in observations and precursors didn't match!"); return }
    if(any(precursors != 0 & precursors != 1)) {
      message("No-binary precursors found. Interpreting all nonzero entries as presence")
      precursors[precursors != 0 & precursors != 1] <- 1
    }
    # check to make sure all precursors states come before their descendants
    precursor.sums = rowSums(precursors)
    if(any(precursor.sums > obs.sums)) {
      message("Precursors found more advanced than observations!")
      return()
    }
    # compile precursor-observations pairs into strings
    precursor.rows = apply(precursors, 1, paste, collaspse="")
    for(i in 1:length(obs.rows)) {
      final.rows[i] <- paste(c(precursor.rows[i], obs.rows[i]), collapse = "")
    }
  }
  
  if(any(obs.sums == 0)) {
    message("Dropping O^L observations")
    #message(getwd())
    final.rows = final.rows[obs.sums]
  }
  
  # create input file for HyperHMM
  filename <- paste(c("HyperHMM-in-", label, ".txt"), collapse="")
  write(final.rows, filename)
  
 
  # create call to HyperHMM
  if(simulate == TRUE) {
    if(fork == TRUE) {
      syscommand <- paste(c(commandname, " ", filename, " ", L, " ", nboot, " ", label, " ", cross.sectional, " ", random.walkers, " &"), collapse = "")
      message(paste(c("Attempting to externally execute ", syscommand), collapse = ""))
      system(syscommand)
      message("Forked: not retrieving output")
      return(NULL)
    } else {
      syscommand <- paste(c(commandname, " ", filename, " ", L, " ", nboot, " ", label, " ", cross.sectional, " ", random.walkers), collapse = "")
      message(paste(c("Attempting to externally execute ", syscommand), collapse = ""))
      system(syscommand)
    }
  }
  
  # attempt to read the output of the run
  mean.filename = paste(c("mean_", label, ".txt"), collapse="")
  sd.filename = paste(c("sd_", label, ".txt"), collapse="")
  transitions.filename = paste(c("transitions_", label, ".txt"), collapse="")
  viz.filename = paste(c("graph_viz_", label, ".txt"), collapse="")
  
  message(paste(c("Attempting to read output... e.g. ", mean.filename), collapse=""))
  if(!(mean.filename %in% list.files()) | !(sd.filename %in% list.files()) | !(transitions.filename %in% list.files()) | !(viz.filename %in% list.files())) {
    message(paste(c("Couldn't find file output of externally executed HyperHMM!"), collapse=""))
    return()
  } else {
    mean.table = read.table(mean.filename)
    file.remove(mean.filename)
    sd.table = read.table(sd.filename)
    file.remove(sd.filename)
    transitions = read.csv(transitions.filename, sep=" ")
    file.remove(transitions.filename)
    viz.tl = readLines(viz.filename)
    file.remove(viz.filename)
    file.remove(filename)
    
    message("All expected files found.")
    L <- nrow(mean.table)
    # pull the wide output data into long format
    stats.df <- data.frame(feature=rep(0, L*L), order = rep(0, L*L),
                           mean = rep(0, L*L), sd = rep(0, L*L))
    index <- 1
    for(i in 1:L) {
      for(j in 1:L) {
        stats.df$feature[index] <- L-i+1
        stats.df$order[index] <- j
        stats.df$mean[index] <- mean.table[i,j]
        stats.df$sd[index] <- sd.table[i,j]
        index <- index+1
      }
    }
    
   
   #Create HyperHMM_trans_mat from transitions (dataframe) 
    
    lista<-lapply(1:length(features),
                  function(y) combn(features,y,simplify=FALSE))
    
    lista<-c('WT',unlist(lapply(lista, 
                  function(y) (lapply(y, function(z) toString(z))))))
    
    M <- matrix(0, nrow = length(lista), ncol = length(lista))
    
    for (i in (1:length(transitions[["Probability"]]))){
      
      M[transitions[["From"]][i],
        transitions[["To"]][i]+1] <- transitions[["Probability"]][i]
    }
    trans_mat <- as(M, "dgCMatrix")
    trans_mat@Dimnames[[1]]<-as.character(lista)
    trans_mat@Dimnames[[2]]<-as.character(lista)
    
    
    #create a list of useful objects and return it
    fitted <- list (stats.df = stats.df, transitions = transitions, 
                   trans_mat = trans_mat, features = features, 
                  viz.tl = viz.tl)

    return(fitted)
  }
}
