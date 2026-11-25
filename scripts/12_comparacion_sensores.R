# Comparación exploratoria Mestech–Mobrey, Cancela Millán, 2026.
# Fuente: ICTS-RBD / EBD-CSIC, Hidromet (CC BY 4.0), descargas 10 y 24/11/2026.
# Ejecutar desde la raíz del repositorio:
# Rscript scripts/12_comparacion_sensores.R RUTA_MESTECH_CSV RUTA_MOBREY_CSV
# No modifica los datos originales. Las métricas son de concordancia, no de exactitud.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop('Indica las rutas de los CSV diarios Mestech y bruto Mobrey.')
m <- read.csv(args[1], comment.char = '#', stringsAsFactors = FALSE)
b <- read.csv(args[2], comment.char = '#', stringsAsFactors = FALSE)
stopifnot(all(c('Date','Value') %in% names(m)), all(c('Date','Value') %in% names(b)))
m$fecha <- as.Date(m$Date)
stopifnot(!anyDuplicated(m$fecha))
b$instante <- as.POSIXct(b$Date, format='%Y-%m-%d %H:%M:%S', tz='UTC')
stopifnot(!anyNA(b$instante), !anyNA(b$Value))
# Una observación por instante: promediar valores discrepantes con igual marca temporal.
# Regla exploratoria pendiente de validación por el equipo técnico.
cat('Filas brutas Mobrey:',nrow(b),'\n')
cat('Marcas temporales repetidas:',sum(duplicated(b$instante)),'\n')
b <- unique(b[c('instante','Value')])
b <- aggregate(Value ~ instante, b, mean)
b$fecha <- as.Date(b$instante, tz='UTC')
a <- aggregate(Value ~ fecha,b,mean); names(a)[2] <- 'mobrey_m'
n <- aggregate(Value ~ fecha,b,length); names(n)[2] <- 'n_mobrey'
m <- m[c('fecha','Value')]; names(m)[2] <- 'mestech_m'
cal <- data.frame(fecha=seq(min(b$fecha), max(b$fecha), by='day'))
d <- Reduce(function(x,y) merge(x,y,by='fecha',all.x=TRUE),list(cal,a,n,m))
d$n_mobrey[is.na(d$n_mobrey)] <- 0L
d$cobertura_mobrey <- d$n_mobrey / 288
d$delta_m <- d$mestech_m-d$mobrey_m
d$comparable <- d$n_mobrey >= ceiling(.8*288) & is.finite(d$delta_m)
d$periodo <- ifelse(d$fecha < as.Date('2026-07-04'),'Antes',ifelse(d$fecha == as.Date('2026-07-04'),'Transicion','Despues'))
met <- function(z) data.frame(n=nrow(z),spearman=cor(z$mestech_m,z$mobrey_m,method='spearman'),pearson=cor(z$mestech_m,z$mobrey_m),sesgo_m=mean(z$delta_m),MAE_m=mean(abs(z$delta_m)),RMSE_m=sqrt(mean(z$delta_m^2)))
z <- d[d$comparable,]
res <- rbind(cbind(periodo='Antes',met(z[z$periodo=='Antes',])),cbind(periodo='Despues',met(z[z$periodo=='Despues',])))
print(res)
dir.create('data/processed',recursive=TRUE,showWarnings=FALSE)
dir.create('figures',recursive=TRUE,showWarnings=FALSE)
write.csv(d,'data/processed/comparacion_mestech_mobrey_diaria.csv',row.names=FALSE)
write.csv(res,'data/processed/comparacion_mestech_mobrey_metricas.csv',row.names=FALSE)
png('figures/comparacion_mestech_mobrey.png',width=1500,height=900,res=150)
par(mar=c(5,5,4,1)); plot(d$fecha,d$mestech_m,type='l',col='firebrick',ylim=range(c(d$mestech_m,d$mobrey_m),na.rm=TRUE),xlab='Fecha (UTC)',ylab='Nivel medio diario (m)',main='Cancela Millán: contraste de sensores')
lines(d$fecha,ifelse(d$n_mobrey>=ceiling(.8*288),d$mobrey_m,NA),col='steelblue'); abline(v=as.Date('2026-07-04'),lty=2); legend('topleft',c('Mestech','Mobrey (cobertura >=80%)'),col=c('firebrick','steelblue'),lty=1,bty='n'); mtext('Fuente: ICTS-RBD / EBD-CSIC, Hidromet (CC BY 4.0)',side=1,line=3.5,cex=.7); dev.off()
