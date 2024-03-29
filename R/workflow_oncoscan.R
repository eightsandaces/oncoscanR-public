# workflow_oncoscan.R
#
# Functions to run the complete workflow from input files to scores and arm-level alterations.
#
# Author: Yann Christinat
# Date: 23.06.2020

#' Run the standard workflow for Oncoscan ChAS files.
#'
#' @details Identifies the globally altered arms (\>=80\% of arm altered), computes the LST, HR-LOH, TD and
#' TD+ scores. The amplification is defined as a CN subtype \code{cntype.weakamp} or
#' \code{cntype.strongamp}. An arm is gained if of CN type \code{cntype.gain} unless the arm is
#' amplified.
#'
#' @param chas.fn Path to the text-export ChAS file
#' @param gender Gender of the sample (M or F)
#'
#' @return A list of lists with the following elements:
#' \code{armlevel = list(AMP= list of arms, GAIN= list of arms, LOSS= list of arms, LOH= list of arms),
#' scores = list(LST= number, LOH= number, TDplus= number),
#' gender = gender as given by the parameter,
#' file = path of the ChAS file as given by the parameter)}
#'
#' @export
#'
#' @import magrittr
#'
#' @examples
#' segs.filename <- system.file("extdata", "chas_example.txt", package = "oncoscanR")
#' workflow_oncoscan.run(segs.filename, "M")
workflow_oncoscan.run <- function(chas.fn, gender){
  if(!(gender %in% c('M', 'F'))){
    stop("The gender (second argument) has to be F or M.")
  }

  # Remove the 21p arm from the Oncoscan coverage as it is only partly covered and we don't
  # want to return results on this arm.
  oncoscan.cov <- oncoscanR::oncoscan_na33.cov[seqnames(oncoscanR::oncoscan_na33.cov) != '21p']

  # Load the ChAS file and assign subtypes.
  segments <- load_chas(chas.fn, oncoscan.cov)
  segments$cn.subtype <- get_cn_subtype(segments, gender)

  # Clean the segments: resctricted to Oncoscan coverage, LOH not overlapping with copy loss
  # segments, smooth&merge segments within 300kb and prune segments smaller than 300kb.
  segs.clean <- trim_to_coverage(segments, oncoscan.cov) %>%
    adjust_loh() %>%
    merge_segments() %>%
    prune_by_size()

  # Split segments by type: Loss, LOH, gain or amplification and get the arm-level alterations.
  # Note that the segments with copy gains include all amplified segments.
  armlevel.loss <- segs.clean[segs.clean$cn.type == cntype.loss] %>%
    armlevel_alt(kit.coverage = oncoscan.cov)
  armlevel.loh <- segs.clean[segs.clean$cn.type == cntype.loh] %>%
    armlevel_alt(kit.coverage = oncoscan.cov)
  armlevel.gain <- segs.clean[segs.clean$cn.type == cntype.gain] %>%
    armlevel_alt(kit.coverage = oncoscan.cov)
  armlevel.amp <- segs.clean[segs.clean$cn.subtype %in% c(cntype.strongamp, cntype.weakamp)] %>%
    armlevel_alt(kit.coverage = oncoscan.cov)

  # Remove amplified segments from armlevel.gain
  armlevel.gain <- armlevel.gain[!(names(armlevel.gain) %in% names(armlevel.amp))]

  # Get the number of LST, LOH, TDplus and TD
  n.lst <- score_lst(segs.clean, oncoscan.cov)

  armlevel.hetloss <- segs.clean[segs.clean$cn.subtype == cntype.hetloss] %>%
    armlevel_alt(kit.coverage = oncoscan.cov)
  n.loh <- score_loh(segs.clean, oncoscan.cov, names(armlevel.loh), names(armlevel.hetloss))
  n.td <- score_td(segs.clean)

  # Get the alterations into a single list and print it in a JSON format.
  armlevel_alt.list <- list(AMP=sort(names(armlevel.amp)),
                            LOSS=sort(names(armlevel.loss)),
                            LOH=sort(names(armlevel.loh)),
                            GAIN=sort(names(armlevel.gain)))
  scores.list <- list(LST=n.lst, LOH=n.loh, TDplus=n.td$TDplus)

  return(list(armlevel=armlevel_alt.list,
       scores=scores.list,
       gender=gender,
       file=basename(chas.fn)))
}
