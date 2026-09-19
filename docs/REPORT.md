# Graph-based Metric Learning for Scene Understanding with Semantic Web Technologies

- **Group ID**: FlyNow
- **Project ID**: 26
- **Componenti del gruppo**: Santi Lisi, Francesco Granata, Dario Lazzara

> Questo documento è la sintesi del progetto. La trattazione completa — derivazioni,
> tabelle estese, appendici su iperparametri e riproducibilità — sta in
> [`relazione.pdf`](relazione.pdf). Le slide della discussione sono in
> [`slides.pdf`](slides.pdf).

---

## 1. Abstract

Il lavoro affronta il recupero di scene visive per *similarità composizionale*: date due
immagini, la somiglianza non è definita da texture o pixel, ma dalle entità presenti e
dalle relazioni che le legano. Le scene di GQA vengono rappresentate come grafi,
arricchite tramite un'ontologia OWL gestita da un triple store Virtuoso e proiettate in
uno spazio metrico a 256 dimensioni da una GNN addestrata in modo contrastivo. La
valutazione, condotta con un motore FAISS su una ground truth semantica, mostra la
superiorità dell'approccio strutturato sulle baseline visive: il modello migliore
raggiunge una HitRate@20 dell'81,58% sul corpus da 15k e del 67,20% su quello da 55k,
con un distacco rispettivamente di +37 e +26 punti su CLIP.

## 2. Introduzione e obiettivi

I modelli di rappresentazione globale — CNN o Vision Transformer — comprimono l'intera
scena in un singolo vettore denso, privilegiando l'apparenza e la frequenza statistica
degli oggetti. La struttura relazionale viene collassata: due scene con gli stessi
elementi in configurazioni logiche opposte (*«uomo cavalca cavallo»* contro *«uomo
accarezza cavallo»*) risultano quasi indistinguibili nello spazio delle feature. È il
noto effetto *bag-of-words*, che affligge anche l'allineamento testo-immagine di CLIP.

Uno scene graph codifica invece esplicitamente le entità come nodi, con i loro attributi,
e le relazioni come archi tipizzati che ne definiscono le interazioni spaziali e d'azione.
L'obiettivo del progetto è costruire e valutare una pipeline end-to-end di
*scene-to-scene retrieval*: data una scena di query espressa come grafo, recuperare da una
galleria su larga scala le scene composizionalmente più simili.

Gli obiettivi minimi della traccia sono coperti dalle baseline visive (§4.4), dal graph
encoder (§4.1), dalle loss contrastive (§4.2) e dal motore di retrieval con le relative
metriche (§6). Sono stati affrontati anche quattro obiettivi extra: infrastruttura cloud e
deployment, robustezza del modello, estrazione dinamica dei grafi tramite VLM e
explainability con `GNNExplainer`.

## 3. Dataset e pipeline dei dati

### 3.1 Estrazione e arricchimento semantico

Il corpus di partenza è **GQA**, di cui sono state usate due scale: un sottoinsieme di
15.410 scene per la messa a punto e il corpus completo di circa 55.000 scene per la
validazione finale. Le annotazioni originali vengono convertite in triple RDF e caricate
in un triple store **Virtuoso**.

Sopra a queste triple opera un'ontologia **OWL 2** modellata in Protégé, con una
tassonomia a tre livelli, assiomi di disgiunzione e vincoli di dominio e codominio sulle
proprietà. L'inferenza espande ogni nodo con le sue macro-categorie: `cat` e `dog`, che
come stringhe non hanno nulla in comune, ereditano entrambe `Animale` e finiscono in
porzioni contigue dello spazio ancora prima di entrare nella rete. La costruzione del
TBox, le catene di proprietà e le query SPARQL usate per collaudare l'inferenza su
Virtuoso sono documentate per esteso in
[`DetailOntologyEnrichment.pdf`](DetailOntologyEnrichment.pdf).

Ogni scena esiste perciò in due varianti, che rendono isolabile il contributo del
ragionamento ontologico: **semantic**, arricchita dalle inferenze, e **baseline**, con le
sole annotazioni GQA.

### 3.2 Rappresentazione dei grafi

Ogni grafo diventa un oggetto `Data` di PyTorch Geometric. Le etichette testuali di nodi e
archi vengono vettorizzate con **NOMIC**, che produce 768 dimensioni sia per `x` (le
entità) sia per `edge_attr` (i predicati). Sul sottoinsieme si contano 189.218 nodi e
422.258 archi complessivi; circa il 6% delle scene è priva di archi, e la pipeline le
tratta come semplici *bag of objects*.

### 3.3 Split del dataset

Gli split sono generati una volta sola con seed fisso 42 e salvati su file, così che ogni
modello legga esattamente le stesse scene negli stessi insiemi e la differenza misurata
dipenda dal metodo e non dal campionamento.

| Split | Subset 15k | Fullset 55k |
|---|---:|---:|
| Train | 10.016 | ~65% |
| Validation | 1.541 | ~10% |
| Gallery | 3.082 | restante (>13.000) |
| Queries | 771 | 1.000 |

L'asimmetria fra query e gallery è voluta: la gallery è lo spazio di ricerca e deve
essere ampia perché il retrieval non risulti banale. Il rimescolamento a scale diverse
produce però array differenti, quindi le 1.000 query del fullset non coincidono con le
771 del subset e **la confrontabilità diretta vale solo all'interno della stessa scala**.

## 4. Metodo

### 4.1 Graph encoder

L'encoder ha tre stadi: tre layer di convoluzione su grafo con dimensione nascosta 256 e
dropout 0,3, un pooling a media globale che riduce il grafo a un vettore, e una testa di
proiezione MLP 256→256→256. L'uscita è normalizzata in norma ℓ2 a 256 dimensioni.

Le due varianti convolutive isolano il peso dell'informazione relazionale.
**GINEConv** è *edge-aware*: incorpora `edge_attr` nel message passing, quindi legge il
predicato. **SAGEConv** vede solo la topologia e ignora l'etichetta dell'arco. Il confronto
fra le due misura direttamente quanto valga sapere *come* due oggetti sono in relazione, e
non solo *che* lo sono.

### 4.2 Funzioni di loss

Sono state confrontate **NT-Xent** (temperatura 0,2) e **Triplet Margin** (margine 0,3 con
semi-hard mining). L'augmentation applicata alle viste rimuove il 10% dei nodi, il 20%
degli archi e maschera il 10% delle feature.

Le due loss trattano i negativi in modo opposto, ed è questa la ragione del divario
osservato nei risultati. NT-Xent normalizza con una softmax su tutto il batch, trattando
ogni elemento non-positivo come un negativo da respingere: in un corpus a densità
composizionale alta come GQA, dentro un batch da 128 finiscono quasi certamente scene
parzialmente affini, e l'esponenziale a denominatore genera gradienti repulsivi contro
scene che affini lo sono davvero, frammentando lo spazio. La Triplet Loss impone invece un
vincolo puramente locale — l'ancora più vicina al positivo che al negativo di almeno un
margine α — e quando la condizione è soddisfatta il gradiente si annulla. Questa
saturazione le dà una tolleranza naturale al rumore dei positivi estratti euristicamente.

### 4.3 Metrica di similarità e ground truth

La stessa metrica serve a due scopi: minare i positivi durante l'addestramento e costruire
la ground truth di valutazione. È una **Jaccard pesata con IDF**, calcolata su due insiemi
per scena — gli oggetti e le triple soggetto-predicato-oggetto — combinati a peso uguale
(0,5 / 0,5). L'IDF serve perché la coda del corpus è lunga: `window`, `man` e `sky`
compaiono in migliaia di scene e non discriminano nulla, mentre un oggetto raro identifica.
Un ulteriore **veto semantico** a 0,55 sugli embedding di scena scarta le coppie che la
regola simbolica accetterebbe ma che semanticamente non stanno insieme, con una soglia di
bypass a 0,30. La soglia minima di similarità è 0,15 e ogni ancora riceve al massimo
cinque positivi.

Il criterio è deterministico e riproducibile, ma va dichiarato che opera sulla struttura
dei grafi: è la principale minaccia alla validità del confronto, discussa in §8.

### 4.4 Baseline di confronto

**ResNet50** e **CLIP ViT-B/32**, entrambi congelati e senza fine-tuning, valutati sugli
stessi split e con la stessa ground truth. Rappresentano i due estremi dello spettro
visivo: il primo addestrato su classificazione supervisionata, il secondo su allineamento
testo-immagine. Servono a quantificare quanto il retrieval composizionale dipenda dalle
relazioni esplicite; non sono modelli concorrenti sul loro terreno.

## 5. Setup sperimentale

Ottimizzatore AdamW, learning rate iniziale 10⁻³, weight decay 10⁻⁴, cosine annealing,
300 epoche, batch da 128. La tabella completa degli iperparametri è in appendice alla
[relazione](relazione.pdf); i file di configurazione stanno in `experiments/configs/`.

Gli addestramenti sono girati su un cluster SLURM dentro un'immagine Apptainer condivisa,
una quota di GPU **NVIDIA L40S**, quattro core e 16 GB per job. Le quattro esecuzioni
definitive sono finite sullo stesso nodo, quindi i tempi sono confrontabili fra loro: tutte
comprese fra i dieci e gli undici minuti. Python 3.11, PyTorch 2.7.1 per CUDA 11.8,
`torch_geometric` 2.8.0.

Lo split e la ground truth sono deterministici. Non sono invece fissati il seed di
inizializzazione dei pesi e quello che governa l'ordine dei batch, quindi **nessuna
configurazione è stata ripetuta** e gli scarti dell'ultimo ordine non vanno letti come
evidenza.

## 6. Risultati

Le tabelle complete, per tutte le fasi di valutazione, stanno in
[`docs/RESULTS.md`](RESULTS.md) e corrispondono a quelle della relazione.
Qui sotto i valori sintetici.

### 6.1 Confronto fra architetture e loss

Subset 15k, configurazione Semantic Web.

| Configurazione | Architettura | Loss | P@1 | P@5 | P@10 | R@10 | Acc@10 | Acc@20 |
|---|---|---|---:|---:|---:|---:|---:|---:|
| Semantic Web | SAGE | NT-Xent | 35.80 | 20.57 | 13.85 | 35.23 | 68.61 | 76.65 |
| Semantic Web | GINE | NT-Xent | 38.39 | 21.74 | 14.51 | 36.38 | 70.04 | 78.34 |
| Semantic Web | SAGE | Triplet | 44.75 | 23.53 | 15.16 | 38.29 | 71.98 | 79.90 |
| Semantic Web | **GINE** | Triplet | **47.34** | **24.85** | **15.71** | **39.85** | **74.45** | **81.58** |

Il salto più grande viene dalla loss, non dall'architettura: passando da NT-Xent a
Triplet la P@1 sale di circa 6-9 punti su entrambe le architetture, mentre lo scarto fra
GINE e SAGE resta fra 1 e 3 punti. Nessuna configurazione è stata ripetuta con seed
diversi, quindi gli scarti dell'ultimo ordine non vanno letti come evidenza di
superiorità.

### 6.2 Effetto dell'arricchimento ontologico

Sul subset l'arricchimento vale +13,23 punti di Acc@20 sul modello di riferimento
(81,58 con Semantic Web contro 68,35 su GQA nativo) e +7,26 su P@1.

Sul full set il vantaggio non si ritrova: 67,20 contro 67,10 ad Acc@20, con il corpus
nativo avanti su P@1 (37,30 contro 36,90). Le due varianti si equivalgono alla scala
piena.

### 6.3 Effetto della scala del corpus

Con la gallery del full set il modello di riferimento passa da 81,58 a 67,20 di Acc@20.
Il calo misura l'allargamento dello spazio di ricerca, non un peggioramento del modello:
la gerarchia fra le configurazioni resta la stessa.

La cross-evaluation zero-shot separa i due effetti. Il modello addestrato su 55k e valutato
sul test set da 15k arriva a 81,71 di Acc@20, sopra al modello addestrato nativamente su
15k. Il percorso inverso, modello 15k sulla gallery da 55k, scende a 49,70.

### 6.4 Confronto con le baseline visive

Encoder visivi congelati, senza fine-tuning, sugli stessi split.

| Corpus | Modello | P@1 | P@10 | Acc@20 |
|---|---|---:|---:|---:|
| 15k | ResNet50 | 23.73 | 6.38 | 44.88 |
| 15k | CLIP ViT-B/32 | 23.73 | 6.86 | 44.36 |
| 15k | GCN GINE + Triplet | 47.34 | 15.71 | 81.58 |
| 55k | ResNet50 | 16.60 | 4.28 | 37.00 |
| 55k | CLIP ViT-B/32 | 20.00 | 5.34 | 41.20 |
| 55k | GCN GINE + Triplet | 36.90 | 10.95 | 67.20 |

Il confronto va letto con una premessa: la ground truth deriva dai grafi, quindi favorisce
per costruzione i modelli che leggono i grafi. Il divario quantifica quanto il retrieval
composizionale dipenda dalle relazioni esplicite, non un fallimento di CLIP sul suo
terreno.

## 7. Analisi

### 7.1 Robustezza alla perturbazione dei grafi

Self-retrieval su 1.000 scene della gallery, modello `gcn_gine_triplet` (Semantic Web),
rimuovendo una quota crescente di nodi. Grafico in `figures/robustness_test_plot.png`.

| Nodi rimossi | 0% | 10% | 20% | 30% | 40% |
|---|---:|---:|---:|---:|---:|
| Acc@20 | 99.80 | 99.20 | 97.50 | 95.10 | 87.20 |
| P@1 | 99.60 | 95.60 | 89.80 | 79.80 | 64.80 |

Fino al 20% di nodi rimossi la Acc@20 perde poco più di due punti. Il calo si fa sentire
su P@1, che scende da 99,60 a 64,80 al 40%.

### 7.2 Explainability

`GNNExplainer` in modalità regression sul grafo, sulla scena GQA 2363112 (11 nodi, 21
archi). I coefficienti più alti vanno a *Hair* (0,093), *Surfboard* (0,087), *Arm*
(0,086) e *Man* (0,085). Lo spread fra i nodi principali è però stretto, quindi la mappa
indica dove si concentra il segnale ma non stabilisce una gerarchia netta fra quei nodi.
Grafico in `figures/explainability_graph.png`.

### 7.3 Infrastruttura Cloud e Deployment

Il sistema è stato sottoposto a un deployment cloud-native su AWS, orchestrato interamente tramite Terraform e script Bash per garantire riproducibilità e Continuous Integration. L'infrastruttura di base sfrutta un cluster Kubernetes (K3s) su istanze EC2, bilanciato da un Application Load Balancer (ALB), con persistenza su RDS (PostgreSQL) e Redis.

Durante la fase di messa in produzione, è emersa una criticità hardware legata al caricamento della galleria dei grafi: il file tensoriale grezzo (`test_gallery_scene_graphs.pt`) pesa oltre 1.1 GB. Il caricamento in RAM tramite `torch.load()` richiedeva oltre 3 GB di memoria scompattata, portando sistematicamente in Out-Of-Memory (OOM) le istanze EC2 di classe `t3.small` (limitate a 2 GB di RAM) e causando un crash irreversibile dell'applicativo (502 Bad Gateway). 

Per risolvere il problema, si è tentato inizialmente uno scale-up verticale passando alle istanze `t3.medium` (4 GB di RAM). Tuttavia, questa soluzione è stata bloccata dalle restrizioni dell'account AWS Free Tier (`FreeTierRestrictionError`), che non consentiva il provisioning di tale classe di macchine. La soluzione definitiva è consistita nell'ottimizzare architetturalmente la pipeline dei dati: il caricamento pesante dei tensori è stato rimosso dai pod applicativi. Al suo posto, un job preparatorio locale esporta i grafi necessari sotto forma di leggeri file JSON (uno per immagine), che vengono sincronizzati su un bucket S3. Il backend interroga direttamente il bucket S3 per recuperare la topologia del grafo su richiesta, abbattendo drasticamente il footprint di memoria e garantendo stabilità sulle macchine `t3.small`.

La gestione del traffico per l'inferenza AI è stata inoltre ottimizzata introducendo l'autoscaling dinamico tramite KEDA (Kubernetes Event-driven Autoscaling). KEDA monitora la lunghezza di una coda SQS dedicata ai job di AI e scala automaticamente il deployment dei worker in base al carico (da un minimo di 1 pod a un massimo di 10), permettendo di smaltire efficientemente i picchi di richieste senza mantenere risorse inutilizzate.

## 8. Limiti e sviluppi futuri

**Circolarità parziale della ground truth.** Il criterio di somiglianza è rule-based e
opera sulla struttura dei grafi. È indispensabile per il determinismo, ma favorisce
strutturalmente i modelli a grafo rispetto alle baseline visive. Il divario di +26-37
punti non va letto come un fallimento di CLIP, ma come la misura di quanto il retrieval
composizionale dipenda dall'esplicitazione delle relazioni.

**Rumore nel mining semantico.** Il controllo incrociato con CLIP come giudice esterno ha
mostrato che circa il 40% dei positivi proposti dal mining non ha una forte somiglianza a
livello di pixel. È la distanza fra somiglianza di scenario — due cucine diverse — e
somiglianza fotografica.

**Dipendenza dalla qualità del grafo in ingresso.** Quando i grafi arrivano da un
estrattore VLM invece che dalle annotazioni, le scene affollate producono allucinazioni e
rumore lessicale che si propagano al retrieval.

**Assenza di ripetizioni.** Nessuna configurazione è stata rieseguita con seed diversi,
quindi le differenze piccole fra celle vicine della griglia non sono interpretabili.

Dall'ispezione dei fallimenti a Top-1 emergono due pattern ricorrenti. Le scene con molti
nodi di sfondo (*sky*, *wall*, *floor*) polarizzano il mean pooling e diluiscono gli
oggetti rari ma distintivi; e nei grafi sparsi con predicati simmetrici la rete fatica a
distinguere la direzionalità, recuperando scene con gli stessi oggetti in ruoli invertiti.

Gli sviluppi naturali seguono da qui: filtri di salienza a monte dell'encoder per scartare
i nodi generici, attenzione sugli archi e pooling gerarchico al posto della media globale,
una validazione umana della ground truth su un sottoinsieme, e una misura end-to-end
dell'intera catena immagine → VLM → grafo → retrieval per quantificare la propagazione
dell'errore.

## 9. Conclusioni

Il progetto mostra che i grafi di scena arricchiti ontologicamente sono una
rappresentazione efficace per il retrieval semantico. La combinazione di convoluzione
edge-aware, regolarizzazione ontologica e Triplet Margin raggiunge l'81,58% di Acc@20 sul
sottoinsieme controllato e il 67,20% sulla galleria estesa, staccando nettamente le
baseline visive non strutturate.

Delle tre leve esaminate la più pesante è risultata la funzione di perdita, non
l'architettura: è il modo in cui lo spazio latente viene vincolato a contare più del
raffinamento del message passing locale. L'arricchimento ontologico è il fattore più
ambivalente — decisivo sul subset, ininfluente alla scala piena, e capire perché il
vantaggio si annulli quando la gallery cresce è la domanda aperta più interessante che
il lavoro lascia.

Le indagini avanzate confermano infine una buona tolleranza alle perturbazioni
strutturali, con l'87,20% di Acc@20 anche rimuovendo il 40% dei nodi, e una generalizzazione
zero-shot che regge il trasferimento dalla scala grande a quella piccola.

---

## Contributi individuali

| Componente | Contributo |
|---|---|
| Santi Lisi | Modellazione dell'ontologia OWL in Protégé, popolamento del triple store Virtuoso e arricchimento inferenziale dei grafi; estensione della pipeline semantica al full set; suddivisione del dataset; infrastruttura cloud e demo. |
| Francesco Granata | Motore di retrieval su FAISS e costruzione degli indici alle due scale; script di valutazione per subset, fullset e cross-evaluation; test di robustezza e analisi di explainability con `GNNExplainer`. |
| Dario Lazzara | Pipeline dei dati ed embedding NOMIC di nodi e archi; ground truth semantica, metrica di similarità e mining dei positivi; graph encoder e funzioni di loss contrastive; addestramenti sul cluster SLURM e studio di ablazione. |

## Uso di strumenti di intelligenza artificiale

Il gruppo ha fatto uso di assistenti conversazionali basati su LLM durante lo sviluppo del
progetto, nei termini che seguono.

**Dove sono stati usati.** Supporto alla scrittura di codice ripetitivo (parsing, script di
I/O, funzioni di plotting), debug di errori di runtime, supporto alla consultazione della
documentazione delle librerie usate, e revisione linguistica della documentazione e della
relazione.

**Dove non sono stati usati.** Le scelte di impostazione del progetto sono state elaborate
dal gruppo: la definizione del criterio di similarità e della ground truth, la scelta
delle architetture e delle funzioni di perdita da confrontare, il disegno del protocollo
sperimentale e l'interpretazione dei risultati. Tutti i numeri riportati provengono da
esecuzioni effettive degli script contenuti in questo repository.

Il gruppo si assume la responsabilità di ogni riga di codice e di ogni affermazione
contenuta in questo documento.

## Riferimenti

- Hudson, D. A., Manning, C. D. — *GQA: A New Dataset for Real-World Visual Reasoning and
  Compositional Question Answering*, CVPR 2019.
- Hu, W. et al. — *Strategies for Pre-training Graph Neural Networks*, ICLR 2020 (GINEConv).
- Hamilton, W. L., Ying, R., Leskovec, J. — *Inductive Representation Learning on Large
  Graphs*, NeurIPS 2017 (GraphSAGE).
- Chen, T. et al. — *A Simple Framework for Contrastive Learning of Visual Representations*,
  ICML 2020 (NT-Xent).
- Schroff, F., Kalenichenko, D., Philbin, J. — *FaceNet: A Unified Embedding for Face
  Recognition and Clustering*, CVPR 2015 (Triplet Loss, semi-hard mining).
- Radford, A. et al. — *Learning Transferable Visual Models From Natural Language
  Supervision*, ICML 2021 (CLIP).
- Douze, M. et al. — *The Faiss Library*, arXiv:2401.08281, 2024.
- Ying, R. et al. — *GNNExplainer: Generating Explanations for Graph Neural Networks*,
  NeurIPS 2019.
