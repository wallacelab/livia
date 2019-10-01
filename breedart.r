library(imager)
library(parallel)

#' Resize a [cimg] object to a specified number of max pixels
#'
#' This function resizes a [cimg] object to have at most a specified number of
#' pixels, using the [imager::imresize()] function. (Images already smaller than
#' this are returned unchanged)
#'
#' @param img A [cimg] image object.
#' @param max_pixels The maximum number of pixels allowed. The image will be
#'   resized to be at or just under this many total pixels while keeping the
#'   same aspect ratio. If the image has multiple frames, all are affected.
#'
#' @return The resized [cimg] object, or the original object if it was already
#'   smaller than `max_pixels`.
#' @export
#'
#' @examples
resize_image = function(img, max_pixels){
  orig_size = height(img) * width(img)
  # If pic is fine (=fewer than max pixels), don't do anything
  if(orig_size <= max_pixels){
    cat("Image is already below",max_pixels,"pixels; returning unchanged\n")
    return(img)
  }

  # Resize anything that is too big
  cat("Resizing image to below",max_pixels,"pixels\n")
  area_ratio = max_pixels / orig_size
  new = imresize(img, scale = sqrt(area_ratio))

  # Return altered image
  return(new)
}


#' Create a random image with the same dimensions as a provided image
#'
#' This function uses a template [cimg] image to create a random image of the
#' same size and color depth (RGB or grayscale).
#'
#' @param img A [cimg] image object.
#'
#' @return a [cimg] image object of the same size but with random pixels.
#' @export
#'
#' @examples
initialize_random = function(img){
  newimage = img
  numpix = width(newimage) * height(newimage)
  # Go through available color channels and randomize to 0-1 range
  for(channel in 1:spectrum(newimage)){
    new_values = runif(numpix)
    newimage[,,,channel] = new_values
  }
  return(newimage)
}

#' Mutate an image object by randomly changing some pixels
#'
#' This function takes a [cimg] image and "mutates" it to randomly change some
#' pixels by a specified amount. The mutation rate and distribution of effects
#' can both be controlled by function arguments.
#'
#' @param img The [cimg] image object to be mutated.
#' @param mutation_rate The probability that any given pixel's value will
#'   mutate.
#' @param mutation_mean The mean of the normal distribution from which mutation
#'   effects are taken. (Generally 0).
#' @param mutation_sd The standard deviation of the normal distribution from
#'   which mutation effects are taken. Larger values are more extreme mutations.
#'   (Remember that [cimg] color values go from 0 to 1, so a `mutation_sd``
#'   value of 1 is actually pretty high.).
#'
#' @return a mutated [cimg] object
#' @export
#'
#' @examples
mutate = function(img, mutation_rate=0.1, mutation_mean=0, mutation_sd=0.1){

  # Determine pixels to mutate
  tochange = sample(c(T,F), size=nPix(img), replace=T,
                    prob=c(mutation_rate, 1-mutation_rate))
  tochange = which(tochange)

  # Get size of mutation
  changes = rnorm(n=length(tochange), mean=mutation_mean, sd=mutation_sd)

  # Mutate pixes
  img[tochange] = img[tochange] + changes

  # fix any pixels that are outside of [0,1]
  img[img < 0] = 0
  img[img > 1] = 1
  return(img)
}

#' Average all images in a list
#'
#' Take a list of [cimg] objects and average them together. All images should
#' have the same dimenstions (height, width, frames, color depth)
#'
#' @param images A [list] of [cimg] objects, all of the same size (height,
#'   width, frames, color depth)
#'
#' @return A single [cimg] object representing the average across all the provided images
#' @export
#'
#' @examples
average_images = function(images){
  avg = images[[1]]
  for(i in 2:length(images)){
    avg = avg + images[[i]]
  }
  avg = avg / length(images)
  return(avg)
}

#' Evolve images to look like a specified target image
#'
#' @param target A [cimg] image object used to select the population of images each generation.
#' @param popsize The size of the image population each generation. (Meaning, how many of the best images are kept each cycle.).
#' @param selection The selection rate, or what fraction of offspring are kept to make the new population. Smaller numbers result in more intense selection.
#' @inheritParams  mutate
#' @param generations How many generations to let the evolution go for.
#' @param mc.cores How many processor cores to run on.
#' @param verbose If TRUE, print out progress reports of population fitness every few generations.
#' @param seed The seed for randomization
#'
#' @return
#' @export
#'
#' @examples
evolve_images = function(target,
                         popsize = 10,
                         selection = 0.1,
                         mutation_rate = 0.1,
                         mutation_mean = 0,
                         mutation_sd = 0.15,
                         generations = 1000,
                         mc.cores=1,
                         verbose=FALSE,
                         seed=NULL) {

  # Set random seed if provided
  if(!is.null(seed)){
    set.seed(seed)
  }

  # Make initial population
  pop = list()
  for(i in 1:popsize){
    pop[[i]] = initialize_random(target)
  }
  # lapply(1:popsize, initialize_random, img=target) # TODO: Figure out why this not working

  # Do evolution
  avg_fitness = rep(NA, generations)
  for(i in 1:generations){
    # Replicate
    replicate_size = popsize / selection
    children = sample(pop, size=replicate_size, replace=T) # TODO: Confirm this taking reps right

    # Mutate
    children = mclapply(children, mutate, mutation_rate=mutation_rate,
                        mutation_mean=mutation_mean, mutation_sd=mutation_sd)

    # Score fitness by correlation with the target image
    fitness = sapply(children, cor, y=target)

    # Keep the best X ones to maintain population size
    tokeep = order(fitness, decreasing=T)[1:popsize]
    pop = children[tokeep]

    # Determine average fitness
    avg_fitness[i] = mean(fitness[tokeep])
    if(verbose && i %% 10 == 0){
      cat("Generation",i,": Average population fitness is",avg_fitness[i],"\n")
    }

  }

  result = list(avg_fitness = avg_fitness, pop=pop, avg_image = average_images(pop))
  return(result)
}

# Function to evolve images for the Shiny app
evolve_images_once = function(target,
						 current_pop = list(),
                         popsize = 10,
                         selection = 0.1,
                         mutation_rate = 0.1,
                         mutation_mean = 0,
                         mutation_sd = 0.15,
                         verbose=FALSE,
                         seed=NULL) {

  # Set random seed if provided
  if(!is.null(seed)){
    set.seed(seed)
  }

  # Make initial population if required
  if(is.null(current_pop$pop)){
	  pop = list()
	  for(i in 1:popsize){
		pop[[i]] = initialize_random(target)
	  }
	  fitness = sapply(pop, cor, y=target)
	  current_pop = list(pop=pop, avg_fitness = mean(fitness), avg_image = average_images(pop))
	  # lapply(1:popsize, initialize_random, img=target) # TODO: Figure out why this not working
  }
	
  # Do evolution

	# Replicate
	replicate_size = popsize / selection
	children = sample(current_pop$pop, size=replicate_size, replace=T) 

	# Mutate
	children = mclapply(children, mutate, mutation_rate=mutation_rate,
						mutation_mean=mutation_mean, mutation_sd=mutation_sd)

	# Score fitness by correlation with the target image
	fitness = sapply(children, cor, y=target)

	# Keep the best X ones to maintain population size
	tokeep = order(fitness, decreasing=T)[1:popsize]
	pop = children[tokeep]

	# Determine average fitness
	avg_fitness = mean(fitness[tokeep])

  result = list(pop=pop, avg_fitness = c(current_pop$avg_fitness, avg_fitness), avg_image = average_images(pop))
  return(result)
}


#' Get mutation size spectrum
#'
#' @param mutation_mean The mean mutation size
#' @param mutation_sd The standard deviation of mutation sizes
#'
#' @return A [data.frame] suitable for plotting the mutation sizes
#' @export
#'
#' @examples
get_mutation_sizes = function(mutation_mean, mutation_sd){

  # Basic distribution
  points = seq(from=-1, to=1, by=0.1)
  density = dnorm(points, mean=mutation_mean, sd=mutation_sd)

  # Add in things outside the -1, 1 range
  lower_tail = pnorm(-1, mean=mutation_mean, sd=mutation_sd, lower.tail=TRUE)
  upper_tail = pnorm(1, mean=mutation_mean, sd=mutation_sd, lower.tail=FALSE)

  density[1] = density[1] + lower_tail
  density[length(density)] = density[length(density)] + upper_tail

  # Return
  return(data.frame(size=points, density=density))
}
