// app.js - Real Backend Integration

/* =========================================
   설정 (Ingress 덕분에 같은 도메인 사용)
   ========================================= */
const API_BASE = "/api"; // Ingress가 '/api'로 시작하면 백엔드로 보내줌

/* =========================================
   1. API 통신 함수들 (S3 & VectorDB & AI)
   ========================================= */

// [AI 채팅] RAG 기반 답변 요청
async function askAI(userMessage) {
    console.log(`[System] Sending prompt to Backend: ${userMessage}`);

    try {
        const response = await fetch(`${API_BASE}/chat`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ query: userMessage })
        });

        if (!response.ok) throw new Error("AI Server Error");

        const data = await response.json();
        
        // 백엔드 응답: { "answer": "...", "context": "..." }
        // context(참고문서 내용)를 기반으로 소스 표시 (파일명 파싱은 생략하거나 context 앞부분 사용)
        return { 
            text: data.answer, 
            sources: data.context ? [{ title: "관련 기술 문서 (RAG)", vendor: "AI Search", type: "DB" }] : [] 
        };

    } catch (error) {
        console.error(error);
        return { text: "죄송합니다. AI 서버 연결에 실패했습니다. (백엔드 상태를 확인해주세요)", sources: [] };
    }
}

// [문서 목록] S3에 있는 파일 리스트 가져오기
async function fetchDocuments() {
    const tbody = document.getElementById('doc-table-body');
    if (!tbody) return; // documents.html이 아니면 중단

    try {
        const response = await fetch(`${API_BASE}/documents`);
        const docs = await response.json();

        tbody.innerHTML = '';

        if (docs.length === 0) {
            tbody.innerHTML = '<tr><td colspan="4" class="p-8 text-center text-slate-500">등록된 문서가 없습니다.</td></tr>';
            return;
        }

        docs.forEach(doc => {
            const tr = document.createElement('tr');
            tr.className = "border-b border-slate-50 hover:bg-slate-50 transition";
            tr.innerHTML = `
                <td class="p-5 font-bold text-slate-700">
                    <i class="far fa-file-alt mr-2 text-indigo-400"></i> ${doc.title}
                </td>
                <td class="p-5"><span class="bg-slate-100 text-slate-500 text-xs px-2 py-1 rounded uppercase">${doc.type}</span></td>
                <td class="p-5 text-sm text-slate-500">${doc.date}</td>
                <td class="p-5 text-right">
                    <button class="text-indigo-600 hover:text-indigo-800 text-sm font-medium">다운로드</button>
                </td>
            `;
            tbody.appendChild(tr);
        });

    } catch (error) {
        console.error(error);
        tbody.innerHTML = '<tr><td colspan="4" class="p-8 text-center text-red-500">데이터를 불러오지 못했습니다.</td></tr>';
    }
}

// [파일 업로드] S3 업로드 & Vector DB 학습
async function uploadDocument(input) {
    const file = input.files[0];
    if (!file) return;

    if (!confirm(`${file.name} 파일을 업로드하고 AI에게 학습시키겠습니까?`)) {
        input.value = '';
        return;
    }

    const formData = new FormData();
    formData.append("file", file);

    // 로딩 표시 (임시)
    alert("업로드 및 학습이 시작되었습니다. 잠시만 기다려주세요...");

    try {
        const response = await fetch(`${API_BASE}/upload`, {
            method: "POST",
            body: formData
        });

        if (response.ok) {
            alert("✅ 업로드 완료! 이제 AI가 이 문서를 이해했습니다.");
            fetchDocuments(); // 목록 새로고침
        } else {
            alert("❌ 업로드 실패. 백엔드 로그를 확인하세요.");
        }
    } catch (error) {
        console.error(error);
        alert("서버 오류 발생");
    }
    input.value = '';
}

// [검색] (현재 백엔드에 단순 검색 API는 없으므로 문서 목록 필터링으로 대체하거나 채팅으로 유도)
async function searchDocs(query) {
    // 실제로는 백엔드의 /api/search를 호출해야 하지만, 
    // 지금은 채팅 기능(askAI)에 집중되어 있으므로 임시로 빈 배열 반환
    return []; 
}


/* =========================================
   2. UI 동작 로직 (기존 코드 유지 및 연결)
   ========================================= */

function handleEnter(event, callback) {
    if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        callback();
    }
}

async function runMainSearch() {
    const input = document.getElementById('main-search-input');
    const query = input.value.trim();
    if(!query) return alert("검색어를 입력해주세요.");

    // 메인 페이지 검색 -> 바로 채팅 페이지로 넘겨서 AI에게 물어보는 UX가 더 자연스러움
    // 현재는 결과 리스트만 보여주는 구조이므로, '검색 결과가 없습니다' 대신 AI 챗봇 유도
    const listContainer = document.getElementById('result-list');
    const resultArea = document.getElementById('search-results');
    
    resultArea.classList.remove('hidden');
    listContainer.innerHTML = `
        <div class="text-center p-6 bg-indigo-50 rounded-xl border border-indigo-100">
            <p class="text-indigo-800 font-bold mb-2">AI에게 직접 물어보세요!</p>
            <p class="text-sm text-indigo-600 mb-4">"${query}"에 대한 내용을 문서에서 찾아 답변해 드립니다.</p>
            <button onclick="location.href='chat.html'" class="bg-indigo-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-indigo-700 transition">
                AI 어시스턴트와 대화하기
            </button>
        </div>
    `;
}

/* =========================================
   3. 채팅 UI 로직
   ========================================= */

async function sendChatMessage() {
    const input = document.getElementById('chat-input');
    const container = document.getElementById('chat-container');
    const message = input.value.trim();

    if (!message) return;

    appendMessage('user', message);
    input.value = '';

    // 로딩 UI
    const loadingId = 'loading-' + Date.now();
    const loadingDiv = document.createElement('div');
    loadingDiv.id = loadingId;
    loadingDiv.className = "flex items-start gap-4 fade-in";
    loadingDiv.innerHTML = `
        <div class="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-white flex-shrink-0 mt-1"><i class="fas fa-robot text-sm"></i></div>
        <div class="bg-white p-4 rounded-2xl rounded-tl-none shadow-sm border border-slate-100 text-slate-500 text-sm">
            <i class="fas fa-circle-notch fa-spin mr-2"></i> 문서를 분석 중입니다...
        </div>`;
    container.appendChild(loadingDiv);
    container.scrollTop = container.scrollHeight;

    // [핵심] 실제 백엔드 호출
    const result = await askAI(message);

    document.getElementById(loadingId).remove();
    appendMessage('ai', result.text);

    if (result.sources && result.sources.length > 0) {
        updateReferences(result.sources);
    }
}

function appendMessage(role, text) {
    const container = document.getElementById('chat-container');
    const div = document.createElement('div');
    div.className = "flex items-start gap-4 fade-in mb-6";
    
    // 텍스트 내의 줄바꿈(\n)을 HTML 태그(<br>)로 변환
    const formattedText = text.replace(/\n/g, '<br>');

    if (role === 'user') {
        div.classList.add('flex-row-reverse');
        div.innerHTML = `
            <div class="w-8 h-8 bg-slate-200 rounded-full flex items-center justify-center text-slate-600 flex-shrink-0 mt-1"><i class="fas fa-user text-sm"></i></div>
            <div class="bg-indigo-600 text-white p-4 rounded-2xl rounded-tr-none shadow-md max-w-2xl text-sm leading-relaxed">${formattedText}</div>
        `;
    } else {
        div.innerHTML = `
            <div class="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-white flex-shrink-0 mt-1"><i class="fas fa-robot text-sm"></i></div>
            <div class="bg-white p-4 rounded-2xl rounded-tl-none shadow-sm border border-slate-100 max-w-2xl text-slate-700 text-sm leading-relaxed">${formattedText}</div>
        `;
    }
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
}

function updateReferences(docs) {
    const container = document.getElementById('ref-container');
    if(!container) return;
    container.innerHTML = ''; 
    
    docs.forEach(doc => {
        const div = document.createElement('div');
        div.className = "bg-white p-3 rounded-lg border border-slate-200 shadow-sm fade-in mb-3";
        div.innerHTML = `
            <div class="flex items-center justify-between mb-1">
                <span class="text-xs font-bold text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded">${doc.vendor}</span>
                <span class="text-xs text-slate-400">RAG</span>
            </div>
            <div class="text-sm font-bold text-slate-700 mb-1">${doc.title}</div>
            <div class="text-xs text-slate-500">문서 내용을 참조하여 답변했습니다.</div>
        `;
        container.appendChild(div);
    });
}