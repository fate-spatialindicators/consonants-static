library(ggplot2)

# bring in various outputs -- use only quadratic results
wc = read.csv("output/wc_output.csv", 
              stringsAsFactors = FALSE)
goa = read.csv("output/goa_output.csv", 
               stringsAsFactors = FALSE)
bc = read.csv("output/bc_output.csv", 
               stringsAsFactors = FALSE)

wc$Region = "COW"
goa$Region="GOA"
bc$Region="BC"
df = rbind(wc,goa,bc) %>% 
  dplyr::filter(quadratic==TRUE) 

# drop out uncertain quadratic models
df = dplyr::mutate(df, quad_cv = abs(b_env2_se/b_env2)) %>%
  dplyr::filter(quad_cv < 0.5)

df$mid = 0.5*(df$hi + df$lo)
df$mid_se = sqrt((0.5^2)*(df$hi_se^2) + (0.5^2)*(df$lo_se^2))

g1 = ggplot(df, aes(mid, range, col=Region)) + 
  geom_vline(aes(xintercept=0),col="grey30") +
  geom_point(size=3,alpha=0.5) + 
  theme_bw() + 
  xlab("Midpoint of estimated thermal niche") + 
  ylab("Range of thermal niche") 


ggsave(plot = g1, filename="plots/Figure_3_alt.png", width = 6, height = 5)
