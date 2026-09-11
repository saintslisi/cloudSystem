import { useState, useEffect } from 'react';
import ReactDOM from 'react-dom';
import './App.css';



const getApiBaseUrl = () => {
  if (typeof window !== 'undefined') {
    if (window.location.port === '5173') {
      return `${window.location.protocol}//${window.location.hostname}:8000`;
    }
    return `${window.location.protocol}//${window.location.hostname}:30080`;
  }
  return 'http://localhost:8000';
};

function App() {
  const API_BASE_URL = getApiBaseUrl();
  const isCloudMode = typeof window !== 'undefined' && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1';
  
  const [file, setFile] = useState(null); // File caricato a sinistra
  const [filePreview, setFilePreview] = useState(null); // URL temporaneo per mostrare l'anteprima dell'immagine caricata
  const [testImages, setTestImages] = useState([]); // Pool di 700 immagini da Postgres
  const [customTestImages, setCustomTestImages] = useState([]); // Immagini caricate dall'utente e salvate
  const [imageTab, setImageTab] = useState('system'); // 'system' o 'custom'
  const [selectedTestImage, setSelectedTestImage] = useState(null); // Immagine selezionata a destra nel carosello

  const [trainingSet, setTrainingSet] = useState('fullset'); // fullset, subset, zeroshot
  const [architecture, setArchitecture] = useState('semantic_web_gcn_gine_triplet'); 
  const [vectorDbSize, setVectorDbSize] = useState('fullset'); // fullset, subset
  const [jobId, setJobId] = useState(null);
  const [jobStatus, setJobStatus] = useState('IDLE');
  const [results, setResults] = useState([]);
  const [errorMessage, setErrorMessage] = useState('');
  const [showResultsScreen, setShowResultsScreen] = useState(false);
  const [selectedResultIndex, setSelectedResultIndex] = useState(0);
  const [useCache, setUseCache] = useState(true);
  const [cachedImages, setCachedImages] = useState({});
  const [saveCustomImageSuccess, setSaveCustomImageSuccess] = useState('');

  // Stati per il Modale del Grafo
  const [showGraphModal, setShowGraphModal] = useState(false);
  const [queryGraph, setQueryGraph] = useState(null);
  const [resultGraph, setResultGraph] = useState(null);
  const [graphError, setGraphError] = useState('');

  const handleCompareGraphs = async () => {
    setGraphError('');
    setQueryGraph(null);
    setResultGraph(null);
    setShowGraphModal(true);

    try {
      const qId = selectedTestImage ? selectedTestImage.id : jobId;
      const rId = results[selectedResultIndex].id;

      const qRes = await fetch(`${API_BASE_URL}/api/v1/graph/${qId}`);
      if (qRes.ok) {
        setQueryGraph(await qRes.json());
      } else {
        setGraphError(`Grafo query non trovato (ID: ${qId})`);
      }

      const rRes = await fetch(`${API_BASE_URL}/api/v1/graph/${rId}`);
      if (rRes.ok) {
        setResultGraph(await rRes.json());
      } else {
        setGraphError(prev => prev + (prev ? ' | ' : '') + `Grafo risultato non trovato (ID: ${rId})`);
      }
    } catch (err) {
      setGraphError("Errore di rete durante il fetch dei grafi.");
    }
  };

  const handleSaveCustomImage = async () => {
    if (!jobId) return;
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/save-custom-image/${jobId}`, {
        method: 'POST'
      });
      const data = await response.json();
      if (response.ok) {
        setSaveCustomImageSuccess("Salvato! L'immagine è ora disponibile in 'Mie Immagini'.");
        fetchCustomTestImages(); // Aggiorna la lista
      } else {
        setSaveCustomImageSuccess(`Errore: ${data.detail || data.message}`);
      }
    } catch (err) {
      setSaveCustomImageSuccess("Errore di rete durante il salvataggio.");
    }
  };

  const handleDeleteCustomImage = async (imageId) => {
    if (!window.confirm("Sei sicuro di voler eliminare questa immagine custom?")) return;
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/custom-test-images/${imageId}`, {
        method: 'DELETE'
      });
      if (response.ok) {
        if (selectedTestImage?.id === imageId) {
          setSelectedTestImage(null);
        }
        fetchCustomTestImages(); // Rinfresca la lista
      } else {
        const data = await response.json();
        alert(`Errore: ${data.detail || data.message}`);
      }
    } catch (err) {
      alert("Errore di rete durante l'eliminazione.");
    }
  };

  const fetchCustomTestImages = async () => {
    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/custom-test-images`);
      const data = await response.json();
      setCustomTestImages(data);
    } catch (err) {
      console.error("Errore caricamento immagini custom:", err);
    }
  };

  useEffect(() => {
    const fetchTestImages = async () => {
      try {
        const response = await fetch(`${API_BASE_URL}/api/v1/test-images`);
        const data = await response.json();
        setTestImages(data);
      } catch (err) {
        console.error("Errore caricamento immagini di test:", err);
      }
    };
    fetchTestImages();
    fetchCustomTestImages();
  }, []);

  // Nuovo useEffect per controllare lo stato della cache per la configurazione corrente
  useEffect(() => {
    const fetchCacheStatus = async () => {
      try {
        const response = await fetch(`${API_BASE_URL}/api/v1/cache-status?training_set=${trainingSet}&architecture=${architecture}&vector_db_size=${vectorDbSize}`);
        const data = await response.json();
        setCachedImages(data);
      } catch (err) {
        console.error("Errore check cache:", err);
      }
    };
    fetchCacheStatus();
  }, [trainingSet, architecture, vectorDbSize]);

  // Gestisce il caricamento del file da PC
  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];
    if (selectedFile) {
      setFile(selectedFile);
      setFilePreview(URL.createObjectURL(selectedFile)); // Genera anteprima locale temporanea
      setSelectedTestImage(null); // Pulisce la selezione del carosello di test (mutua esclusione)
    }
  };

  const handleSelectTestImage = (img) => {
    setSelectedTestImage(img);
    setFile(null); // Pulisce il file caricato (mutua esclusione)
    setFilePreview(null);
  };

  // Invia i dati in base all'ultima selezione effettuata
  const handleSubmit = async (e) => {
    e.preventDefault();
    setErrorMessage('');

    if (!file && !selectedTestImage) {
      setErrorMessage("Carica un'immagine a sinistra OR seleziona un'immagine di test a destra prima di cercare!");
      return;
    }
    setShowResultsScreen(false);

    const formData = new FormData();
    if (file) {
      formData.append('file', file);
    } else {
      formData.append('test_image_id', selectedTestImage.id);
    }
    formData.append('training_set', trainingSet);
    formData.append('architecture', architecture);
    formData.append('vector_db_size', vectorDbSize);
    formData.append('use_cache', useCache);

    try {
      const response = await fetch(`${API_BASE_URL}/api/v1/search`, {
        method: 'POST',
        body: formData
      });
      const data = await response.json();
      setJobId(data.job_id);
      setJobStatus("PROCESSING");
    } catch (err) {
      setErrorMessage("Errore durante l'invio della richiesta.");
    }
  };

  useEffect(() => {
    if (!jobId || jobStatus === 'IDLE' || jobStatus === 'COMPLETED' || jobStatus === 'FAILED') return;

    const checkStatus = async () => {
      try {
        const res = await fetch(`${API_BASE_URL}/api/v1/status/${jobId}`);
        const data = await res.json();
        const currentStatus = data.job.status;

        if (currentStatus === 'COMPLETED') {
          setJobStatus('COMPLETED');
          const resResults = await fetch(`${API_BASE_URL}/api/v1/results/${jobId}`);
          const resultsData = await resResults.json();
          setResults(resultsData);
          setSelectedResultIndex(0);
        } else if (currentStatus === 'FAILED') {
          setJobStatus('FAILED');
          setErrorMessage("L'elaborazione del job è fallita.");
        } else {
          // Aggiorna lo stato per mostrare a che punto è la pipeline
          setJobStatus(currentStatus);
        }
      } catch (err) {
        console.error(err);
      }
    };

    const interval = setInterval(checkStatus, 1000); // Polling più veloce per reattività
    return () => clearInterval(interval);
  }, [jobId, jobStatus]);

  return (
    <div className="app-container">
      <header className="app-header">
        <h1>AI Semantic Search Engine</h1>
        <p>Trova immagini simili caricando una foto o seleziona un'immagine di test precaricata.</p>
      </header>

      <main className="main-content">
        {errorMessage && <div className="error-banner">{errorMessage}</div>}

        {(jobStatus === 'IDLE' || jobStatus === 'FAILED') && (
          <form onSubmit={handleSubmit} className="search-form">

            {/* Contenitore a due colonne */}
            <div className="columns-container">

              {/* COLONNA SINISTRA: Upload Immagine */}
              <div className="column upload-column glass-card">
                <h3>🖼️ Carica Nuova Immagine</h3>
                <div className="upload-wrapper">
                  <div className="image-preview-box">
                    {filePreview ? (
                      <img src={filePreview} alt="Preview" className="preview-img" />
                    ) : (
                      <div className="placeholder-text">Nessuna immagine caricata</div>
                    )}
                  </div>
                  <label htmlFor="file-upload" className="custom-file-upload">
                    Seleziona File
                  </label>
                  <input
                    id="file-upload"
                    type="file"
                    accept="image/*"
                    onChange={handleFileChange}
                  />
                </div>
              </div>

              <div className="vertical-divider"></div>

              {/* COLONNA DESTRA: Carosello Verticale di Test */}
              <div className="column carousel-column glass-card">
                <h3>🧪 Seleziona Immagine di Test</h3>
                
                {/* TAB SELECTOR */}
                <div style={{ display: 'flex', gap: '10px', marginBottom: '15px' }}>
                  <button 
                    type="button" 
                    className={`submit-btn ${imageTab === 'system' ? '' : 'inactive'}`} 
                    onClick={() => { setImageTab('system'); setSelectedTestImage(null); }}
                    style={{ padding: '8px 12px', fontSize: '0.9rem', backgroundColor: imageTab === 'system' ? '#8b5cf6' : '#334155' }}
                  >
                    Immagini di Sistema
                  </button>
                  <button 
                    type="button" 
                    className={`submit-btn ${imageTab === 'custom' ? '' : 'inactive'}`} 
                    onClick={() => { setImageTab('custom'); setSelectedTestImage(null); }}
                    style={{ padding: '8px 12px', fontSize: '0.9rem', backgroundColor: imageTab === 'custom' ? '#8b5cf6' : '#334155' }}
                  >
                    Mie Immagini
                  </button>
                </div>

                <div className="vertical-carousel">
                  {(imageTab === 'system' ? testImages : customTestImages).map((img) => (
                    <div
                      key={img.id}
                      className={`carousel-item ${selectedTestImage?.id === img.id ? 'selected' : ''}`}
                      onClick={() => handleSelectTestImage(img)}
                    >
                      <img
                        src={imageTab === 'system' 
                          ? `${API_BASE_URL}/static/test_images/${img.filename}` 
                          : `${API_BASE_URL}/static/test_images/${img.filename}`}
                        alt={img.name}
                      />
                      {imageTab === 'custom' && (
                        <button
                          className="delete-custom-btn"
                          title="Elimina Immagine"
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDeleteCustomImage(img.id);
                          }}
                        >
                          ×
                        </button>
                      )}
                      <div className="item-info">
                        <p style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '5px' }}>
                          <span title={img.id}>ID: {img.id.toString().length > 10 ? img.id.toString().substring(0, 8) + '...' : img.id}</span>
                          {cachedImages[img.id.toString()] && cachedImages[img.id.toString()].redis && cachedImages[img.id.toString()].postgres && (
                            <span title="Risultato in Cache (Redis + Postgres) ⚡" style={{ cursor: 'help' }}>⚡</span>
                          )}
                          {cachedImages[img.id.toString()] && !cachedImages[img.id.toString()].redis && cachedImages[img.id.toString()].postgres && (
                            <span title="Risultato in Cache (Solo Postgres) 🐘" style={{ cursor: 'help' }}>🐘</span>
                          )}
                          {cachedImages[img.id.toString()] && cachedImages[img.id.toString()].redis && !cachedImages[img.id.toString()].postgres && (
                            <span title="Risultato in Cache (Solo Redis) 🔴" style={{ cursor: 'help' }}>🔴</span>
                          )}
                        </p>
                      </div>
                    </div>
                  ))}
                  {imageTab === 'custom' && customTestImages.length === 0 && (
                    <div style={{ gridColumn: '1 / -1', textAlign: 'center', color: '#94a3b8', padding: '2rem' }}>
                      Nessuna immagine personalizzata salvata.<br/>
                      Carica un'immagine, cerca e salvala dai risultati!
                    </div>
                  )}
                </div>
              </div>

            </div>

            {/* SELEZIONE MODELLO E DATASET (Cross-Evaluation) */}
            <div className="options-container glass-card" style={{ marginTop: '20px', padding: '15px', display: 'flex', flexDirection: 'column', gap: '15px', alignItems: 'center' }}>
              
              <div style={{ display: 'flex', gap: '20px' }}>
                <div className="option-group">
                  <label htmlFor="training_set"><strong>Pesi Rete (Modello):</strong></label>
                  <select 
                    id="training_set" 
                    value={trainingSet} 
                    onChange={(e) => {
                      setTrainingSet(e.target.value);
                      if (e.target.value === 'zeroshot') {
                        setArchitecture('vision_resnet');
                      } else {
                        setArchitecture('semantic_web_gcn_gine_triplet');
                      }
                    }}
                    style={{ marginLeft: '10px', padding: '8px', borderRadius: '5px' }}
                  >
                    <option value="fullset">Fullset 55k (Definitivo)</option>
                    {!isCloudMode && <option value="subset">Subset (Sperimentale)</option>}
                    <option value="zeroshot">Zero-Shot (Baseline Visiva)</option>
                  </select>
                </div>

                <div className="option-group">
                  <label htmlFor="architecture"><strong>Architettura:</strong></label>
                  <select 
                    id="architecture" 
                    value={architecture} 
                    onChange={(e) => setArchitecture(e.target.value)}
                    style={{ marginLeft: '10px', padding: '8px', borderRadius: '5px' }}
                  >
                    {trainingSet === 'zeroshot' ? (
                      <>
                        <option value="vision_resnet">ResNet50 (Baseline)</option>
                        <option value="vision_clip">CLIP (Baseline)</option>
                      </>
                    ) : (
                      <>
                        <optgroup label="GCN Semantic Web (Con Ontologia)">
                          <option value="semantic_web_gcn_gine_triplet">GCN GINE Triplet</option>
                          <option value="semantic_web_gcn_sage_triplet">GCN SAGE Triplet</option>
                          <option value="semantic_web_gcn_gine_ntxent">GCN GINE NTXent</option>
                          <option value="semantic_web_gcn_sage_ntxent">GCN SAGE NTXent</option>
                        </optgroup>
                        
                        {!isCloudMode && (
                          <optgroup label="GCN Baseline (Senza Ontologia)">
                            <option value="baseline_gcn_gine_triplet">GCN GINE Triplet</option>
                            <option value="baseline_gcn_sage_triplet">GCN SAGE Triplet</option>
                            <option value="baseline_gcn_gine_ntxent">GCN GINE NTXent</option>
                            <option value="baseline_gcn_sage_ntxent">GCN SAGE NTXent</option>
                          </optgroup>
                        )}
                      </>
                    )}
                  </select>
                </div>
              </div>

              <div className="option-group" style={{ borderTop: '1px solid #ccc', paddingTop: '15px', width: '100%', textAlign: 'center' }}>
                <label htmlFor="vector_db_size"><strong>Galleria di Ricerca (Vector DB FAISS):</strong></label>
                <select 
                  id="vector_db_size" 
                  value={vectorDbSize} 
                  onChange={(e) => setVectorDbSize(e.target.value)}
                  style={{ marginLeft: '10px', padding: '8px', borderRadius: '5px' }}
                >
                  <option value="fullset">Fullset (~20k immagini test)</option>
                  {!isCloudMode && <option value="subset">Subset (~3k immagini test)</option>}
                </select>
              </div>
            </div>

            {/* PULSANTE UNICO IN BASSO E CHECKBOX CACHE */}
            <div className="submit-section" style={{ marginTop: '20px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '15px' }}>
              <div className="cache-toggle" style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <input 
                  type="checkbox" 
                  id="use_cache" 
                  checked={useCache} 
                  onChange={(e) => setUseCache(e.target.checked)}
                  style={{ transform: 'scale(1.2)' }}
                />
                <label htmlFor="use_cache" style={{ cursor: 'pointer', fontWeight: '500' }}>
                  ⚡ Abilita Ricerca Veloce (Cache)
                </label>
              </div>
              <button
                type="submit"
                className="submit-btn"
                disabled={!file && !selectedTestImage}
              >
                Avvia Ricerca
              </button>
            </div>

          </form>
        )}

        {/* STATO PROCESSING (PIPELINE) */}
        {jobStatus !== 'IDLE' && jobStatus !== 'FAILED' && !showResultsScreen && (
          <div className="glass-card loader-card pipeline-card">
            <h3>{jobStatus === 'COMPLETED' ? 'Ricerca Completata!' : 'Elaborazione Pipeline AI in corso...'}</h3>
            <span className="job-id-tag">ID: {jobId}</span>
            <p className="status-label">Stato attuale: <strong>{jobStatus}</strong></p>
            
            <div className="pipeline-container">
              
              <div className="pipeline-step active">
                <img 
                  src={filePreview || (selectedTestImage ? `${API_BASE_URL}/static/test_images/${selectedTestImage.filename}` : '')} 
                  alt="Query" 
                  className="node-image" 
                />
                <p>Immagine Query</p>
              </div>
              <div className="pipeline-connector"></div>

              <div className={`pipeline-step ${['VLM_INFERENCE', 'SCENE_GRAPH', 'NOMIC_EMBEDDING', 'GCN', 'VECTOR_SEARCH', 'COMPLETED'].includes(jobStatus) ? 'active' : ''}`}>
                <div className={`step-icon ${jobStatus === 'VLM_INFERENCE' || jobStatus === 'SCENE_GRAPH' ? 'pulsing' : ''}`}>🧠</div>
                <p>{file ? 'VLM / Scene Graph' : 'Recupero Scene Graph'}</p>
              </div>
              <div className="pipeline-connector"></div>

              <div className={`pipeline-step ${['NOMIC_EMBEDDING', 'GCN', 'VECTOR_SEARCH', 'COMPLETED'].includes(jobStatus) ? 'active' : ''}`}>
                <div className={`step-icon ${jobStatus === 'NOMIC_EMBEDDING' ? 'pulsing' : ''}`}>🔢</div>
                <p>Nomic Embeddings</p>
              </div>
              <div className="pipeline-connector"></div>

              <div className={`pipeline-step ${['GCN', 'VECTOR_SEARCH', 'COMPLETED'].includes(jobStatus) ? 'active' : ''}`}>
                <div className={`step-icon ${jobStatus === 'GCN' ? 'pulsing' : ''}`}>🕸️</div>
                <p>GCN</p>
              </div>
              <div className="pipeline-connector"></div>

              <div className={`pipeline-step ${['VECTOR_SEARCH', 'COMPLETED'].includes(jobStatus) ? 'active' : ''}`}>
                <div className={`step-icon ${jobStatus === 'VECTOR_SEARCH' ? 'pulsing' : ''}`}>🔍</div>
                <p>Vector Search</p>
              </div>
              <div className="pipeline-connector"></div>

              <div className={`pipeline-step ${jobStatus === 'COMPLETED' ? 'active pulsing' : ''}`}>
                {jobStatus === 'COMPLETED' && results.length > 0 ? (
                  <img src={`${API_BASE_URL}/static/vectorDB/${results[0].id}.jpg`} alt="Match" className="node-image" />
                ) : (
                  <div className="step-icon">🖼️</div>
                )}
                <p>Match Trovato</p>
              </div>

            </div>

            {jobStatus === 'COMPLETED' && (
              <button className="submit-btn view-result-btn" onClick={() => setShowResultsScreen(true)}>
                👁️ Visualizza Risultato
              </button>
            )}
          </div>
        )}

        {/* VISTA COMPARATIVA (COMPLETED) */}
        {showResultsScreen && jobStatus === 'COMPLETED' && (
          <div className="comparison-view">
            
            {/* CAROSELLO RISULTATI IN ALTO */}
            {results.length > 0 && (
              <div className="top-results-carousel-section">
                <h2>Risultati Trovati ({results.length})</h2>
                <div className="results-carousel-container">
                  {results.map((res, index) => (
                    <div 
                      key={res.id} 
                      className={`carousel-result-item ${index === selectedResultIndex ? 'selected' : ''}`}
                      onClick={() => setSelectedResultIndex(index)}
                    >
                      <img 
                        src={`${API_BASE_URL}/static/vectorDB/${res.id}.jpg`} 
                        alt={`Match ${index}`} 
                        onError={(e) => { e.target.src = "https://via.placeholder.com/120x120?text=Error" }}
                      />
                      <div className="carousel-score-badge">{(res.score).toFixed(1)}%</div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            <div className="comparison-columns">
              
              <div className="comparison-card glass-card">
                <h2>Immagine Originale</h2>
                <div className="large-image-wrapper">
                  <img 
                    src={filePreview || (selectedTestImage ? `${API_BASE_URL}/static/test_images/${selectedTestImage.filename}` : '')} 
                    alt="Originale" 
                    className="large-image" 
                  />
                </div>
              </div>

              <div className="comparison-card glass-card result-highlight">
                <h2>{selectedResultIndex === 0 ? "Miglior Risultato" : `Risultato Selezionato (#${selectedResultIndex + 1})`}</h2>
                <div className="large-image-wrapper">
                  {results.length > 0 && results[selectedResultIndex] && (
                    <img 
                      src={`${API_BASE_URL}/static/vectorDB/${results[selectedResultIndex].id}.jpg`} 
                      alt="Risultato" 
                      className="large-image" 
                      onError={(e) => { e.target.src = "https://via.placeholder.com/600x600?text=Immagine+Non+Trovata" }}
                    />
                  )}
                </div>
                {results.length > 0 && results[selectedResultIndex] && (
                  <div className="match-badge-large">Match: {(results[selectedResultIndex].score).toFixed(1)}%</div>
                )}
              </div>

            </div>
            
            <div style={{ marginTop: '30px', marginBottom: '20px', display: 'flex', justifyContent: 'center', gap: '15px', flexWrap: 'wrap' }}>
              <button className="submit-btn" onClick={handleCompareGraphs} style={{ backgroundColor: '#8b5cf6', padding: '12px 24px', fontSize: '1.1rem' }}>
                🔍 Confronta Scene Graph (Debug)
              </button>
              
              {file && (
                <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  <button 
                    className="submit-btn" 
                    onClick={handleSaveCustomImage} 
                    style={{ backgroundColor: '#10b981', padding: '12px 24px', fontSize: '1.1rem' }}
                  >
                    💾 Salva Immagine nel Sistema
                  </button>
                  {saveCustomImageSuccess && (
                    <span style={{ marginTop: '10px', color: saveCustomImageSuccess.includes('Errore') ? '#ef4444' : '#10b981', fontSize: '0.9rem' }}>
                      {saveCustomImageSuccess}
                    </span>
                  )}
                </div>
              )}
            </div>

            <button
              type="button"
              className="reset-btn"
              onClick={() => {
                setJobStatus('IDLE');
                setJobId(null);
                setFile(null);
                setFilePreview(null);
                setSelectedTestImage(null);
                setResults([]);
                setErrorMessage('');
                setShowResultsScreen(false);
                setSelectedResultIndex(0);
              }}
            >
              🔄 Torna alla Ricerca
            </button>
          </div>
        )}

      </main>
      
      {/* MODALE CONFRONTO GRAFI (spostato fuori per full-screen e renderizzato tramite Portal) */}
      {showGraphModal && ReactDOM.createPortal(
        <div className="modal-overlay" onClick={() => setShowGraphModal(false)}>
          <div className="modal-content" onClick={e => e.stopPropagation()}>
            <div className="modal-header">
              <h2>🔍 Confronto Scene Graph</h2>
              <button className="close-btn" onClick={() => setShowGraphModal(false)}>✖</button>
            </div>
            
            {graphError && <div className="error-banner">{graphError}</div>}
            
            <div className="graph-comparison-container">
              <div className="graph-pane">
                <h3>Immagine Originale</h3>
                {queryGraph ? (
                  <div className="graph-data">
                    <h4>Nodi ({queryGraph.nodes.length})</h4>
                    <ul className="graph-list">
                      {queryGraph.nodes.map(n => <li key={n.id}><strong>{n.id}:</strong> {n.label}</li>)}
                    </ul>
                    <h4>Archi ({queryGraph.edges.length})</h4>
                    <ul className="graph-list">
                      {queryGraph.edges.map((e, i) => <li key={i}><strong>{e.source}</strong> <span style={{color:'#8b5cf6'}}>➔ {e.label} ➔</span> <strong>{e.target}</strong></li>)}
                    </ul>
                  </div>
                ) : <p>Caricamento...</p>}
              </div>

              <div className="graph-pane">
                <h3>Risultato (ID: {results[selectedResultIndex]?.id})</h3>
                {resultGraph ? (
                  <div className="graph-data">
                    <h4>Nodi ({resultGraph.nodes.length})</h4>
                    <ul className="graph-list">
                      {resultGraph.nodes.map(n => <li key={n.id}><strong>{n.id}:</strong> {n.label}</li>)}
                    </ul>
                    <h4>Archi ({resultGraph.edges.length})</h4>
                    <ul className="graph-list">
                      {resultGraph.edges.map((e, i) => <li key={i}><strong>{e.source}</strong> <span style={{color:'#8b5cf6'}}>➔ {e.label} ➔</span> <strong>{e.target}</strong></li>)}
                    </ul>
                  </div>
                ) : <p>Caricamento...</p>}
              </div>
            </div>
          </div>
        </div>,
        document.body
      )}
    </div>
  );
}

export default App;
