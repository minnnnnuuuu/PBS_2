// app.js - Search(Index) vs Chat(AI) Logic Separated

const API_BASE = "/api";
let ALL_DOCS = []; // 서버에서 받아온 전체 문서를 담을 그릇

/* =========================================
   1. 데이터 초기화 (페이지 로드 시)
   ========================================= */
document.addEventListener('DOMContentLoaded', async () => {
    await loadAllDocuments();
});

// S3에서 모든 파일 목록 가져오기
async function loadAllDocuments() {
    try {
        const response = await fetch(`${API_BASE}/documents`);
        if (!response.ok) throw new Error("API Load Failed");
        
        const docs = await response.json();
        // 날짜 최신순 정렬
        ALL_DOCS = docs.sort((a, b) => new Date(b.date) - new Date(a.date));

        // [페이지별 초기화]
        
        // 1. 문서 보관함 페이지 (documents.html)
        if (document.getElementById('doc-table-body')) {
            renderDocTable(ALL_DOCS);
        }

        // 2. 메인 페이지 (index.html) - 최신글 3개 보여주기
        if (document.getElementById('latest-docs-grid')) {
            renderLatestUpdates(ALL_DOCS.slice(0, 3));
        }

    } catch (error) {
        console.error("문서 로딩 실패:", error);
    }
}

/* =========================================
   2. [메인 페이지] 검색 엔진 로직 (index.html)
   ========================================= */

// 엔터키 감지
function handleEnter(event, callback) {
    if (event.key === 'Enter') {
        event.preventDefault();
        callback();
    }
}

// ★ 핵심: 파일명/벤더명으로 문서 찾기 (AI 답변 아님!)
async function runMainSearch() {
    const input = document.getElementById('main-search-input');
    const query = input.value.trim().toLowerCase(); // 소문자로 변환해 검색
    const resultArea = document.getElementById('search-results');
    const listContainer = document.getElementById('result-list');

    if (!query) return alert("검색어를 입력해주세요.");

    // 결과 영역 표시
    resultArea.classList.remove('hidden');
    listContainer.innerHTML = ''; 

    // [검색 로직] 제목(Title)이나 벤더(Vendor)에 검색어가 포함된 문서 찾기
    // 예: "aws" 검색 -> "AWS EKS Guide.pdf" 발견
    const matchedDocs = ALL_DOCS.filter(doc => 
        (doc.title && doc.title.toLowerCase().includes(query)) || 
        (doc.vendor && doc.vendor.toLowerCase().includes(query))
    );

    // [결과 렌더링]
    if (matchedDocs.length > 0) {
        // 1. 찾은 문서들을 카드 형태로 보여줌
        listContainer.innerHTML = `<p class="text-sm text-slate-500 mb-3 font-bold"><i class="fas fa-check text-green-500 mr-2"></i>'${input.value}' 관련 문서를 ${matchedDocs.length}건 찾았습니다.</p>`;
        
        matchedDocs.forEach(doc => {
            listContainer.appendChild(createDocCard(doc));
        });
    } else {
        // 2. 문서가 없으면 -> "AI에게 물어보세요" 제안
        listContainer.innerHTML = `
            <div class="text-center p-8 bg-slate-50 rounded-xl border border-slate-200">
                <div class="text-4xl text-slate-300 mb-3"><i class="far fa-folder-open"></i></div>
                <p class="text-slate-700 font-bold mb-1">'${input.value}'와(과) 일치하는 문서 제목이 없습니다.</p>
                <p class="text-sm text-slate-500 mb-6">하지만 문서 내용 중에 포함되어 있을 수 있습니다.</p>
                
                <button onclick="goToChat('${input.value}')" class="bg-indigo-600 text-white px-5 py-3 rounded-xl text-sm font-bold hover:bg-indigo-700 transition shadow-lg flex items-center justify-center gap-2 mx-auto">
                    <i class="fas fa-robot"></i> AI에게 내용 찾아달라고 하기
                </button>
            </div>
        `;
    }
}

// 검색어 들고 채팅방으로 이동하는 함수
function goToChat(query) {
    localStorage.setItem("chatInitQuery", query); // 검색어 저장
    location.href = "chat.html"; // 이동
}

/* =========================================
   3. [채팅 페이지] AI 답변 로직 (chat.html)
   ========================================= */

// 채팅 페이지 로드 시, 메인에서 넘어온 검색어가 있으면 바로 질문 던지기
if (window.location.pathname.includes('chat.html')) {
    const initQuery = localStorage.getItem("chatInitQuery");
    if (initQuery) {
        setTimeout(() => {
            document.getElementById('chat-input').value = initQuery; // 입력창에 넣고
            sendChatMessage(); // 바로 전송
            localStorage.removeItem("chatInitQuery"); // 삭제
        }, 500);
    }
}

// AI에게 질문하기
async function sendChatMessage() {
    const input = document.getElementById('chat-input');
    const container = document.getElementById('chat-container');
    const message = input.value.trim();

    if (!message) return;

    // 1. 사용자 말풍선 추가
    appendMessage('user', message);
    input.value = '';

    // 2. 로딩 표시
    const loadingId = 'loading-' + Date.now();
    const loadingDiv = document.createElement('div');
    loadingDiv.id = loadingId;
    loadingDiv.className = "flex items-start gap-4 fade-in";
    loadingDiv.innerHTML = `
        <div class="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-white flex-shrink-0 mt-1"><i class="fas fa-robot text-sm"></i></div>
        <div class="bg-white p-4 rounded-2xl rounded-tl-none shadow-sm border border-slate-100 text-slate-500 text-sm">
            <i class="fas fa-circle-notch fa-spin mr-2"></i> 문서를 읽고 답변을 생성 중입니다...
        </div>`;
    container.appendChild(loadingDiv);
    container.scrollTop = container.scrollHeight;

    try {
        // 3. 백엔드(AI) 호출
        const response = await fetch(`${API_BASE}/chat`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ query: message })
        });

        if (!response.ok) throw new Error("AI Error");
        const data = await response.json();

        // 4. 로딩 제거 및 AI 답변 말풍선 추가
        document.getElementById(loadingId).remove();
        appendMessage('ai', data.answer);

        // 5. 참고한 문서가 있다면 우측 패널 업데이트
        if (data.context) {
            updateReferences([{ title: "AI 검색 결과", vendor: "RAG System", type: "Context" }]);
        }

    } catch (error) {
        document.getElementById(loadingId).remove();
        appendMessage('ai', "죄송합니다. 서버 연결에 실패했습니다.");
        console.error(error);
    }
}

function appendMessage(role, text) {
    const container = document.getElementById('chat-container');
    const div = document.createElement('div');
    div.className = "flex items-start gap-4 fade-in mb-6";
    const formattedText = text.replace(/\n/g, '<br>'); // 줄바꿈 처리

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

// 우측 참고 문서 패널 (채팅 페이지용)
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
                <span class="text-xs text-slate-400">REF</span>
            </div>
            <div class="text-sm font-bold text-slate-700 mb-1">${doc.title}</div>
        `;
        container.appendChild(div);
    });
}


/* =========================================
   4. UI 공통 요소 (카드 생성, 최신글 등)
   ========================================= */

// 문서 카드 생성기 (index.html 검색결과 & 최신글용)
function createDocCard(doc) {
    const div = document.createElement('div');
    div.className = "bg-white p-5 rounded-xl border border-slate-200 hover:border-indigo-300 hover:shadow-lg transition cursor-pointer group fade-in mb-3";
    
    // 클릭 시 상세 정보창 열기
    div.onclick = () => openDocumentDetail(doc);

    // 확장자별 아이콘
    let iconClass = "fas fa-file-alt";
    let colorClass = "bg-slate-50 text-slate-500";
    if (doc.type && doc.type.toLowerCase().includes('pdf')) { iconClass = "fas fa-file-pdf"; colorClass = "bg-red-50 text-red-600"; }
    else if (doc.type && doc.type.toLowerCase().includes('doc')) { iconClass = "fas fa-file-word"; colorClass = "bg-blue-50 text-blue-600"; }

    div.innerHTML = `
        <div class="flex justify-between items-start mb-3">
            <div class="w-10 h-10 ${colorClass} rounded-lg flex items-center justify-center text-xl"><i class="${iconClass}"></i></div>
            <span class="bg-slate-100 text-slate-500 text-xs px-2 py-1 rounded uppercase">${doc.type || 'FILE'}</span>
        </div>
        <div class="font-bold text-slate-800 mb-1 group-hover:text-indigo-600 transition truncate">${doc.title}</div>
        <div class="text-xs text-slate-400 flex justify-between">
            <span>${doc.vendor || 'Unknown'}</span>
            <span>${doc.date || ''}</span>
        </div>
    `;
    return div;
}

// 메인 페이지 최신글 3개 렌더링
function renderLatestUpdates(docs) {
    const container = document.getElementById('latest-docs-grid');
    if (!container) return;
    container.innerHTML = '';

    if (docs.length === 0) {
        container.innerHTML = '<div class="col-span-3 text-center py-10 text-slate-400">등록된 최신 문서가 없습니다.</div>';
        return;
    }

    docs.forEach(doc => {
        container.appendChild(createDocCard(doc));
    });
}

// 문서 보관함 페이지 리스트 렌더링
function renderDocTable(docs) {
    const tbody = document.getElementById('doc-table-body');
    if (!tbody) return;
    tbody.innerHTML = '';
    
    if (docs.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="p-8 text-center text-slate-500">등록된 문서가 없습니다.</td></tr>';
        return;
    }

    docs.forEach(doc => {
        const tr = document.createElement('tr');
        tr.className = "border-b border-slate-50 hover:bg-slate-50 transition cursor-pointer";
        tr.onclick = () => openDocumentDetail(doc);
        tr.innerHTML = `
            <td class="p-5 font-bold text-slate-700"><i class="far fa-file-alt mr-2 text-indigo-400"></i> ${doc.title}</td>
            <td class="p-5"><span class="bg-slate-100 text-slate-500 text-xs px-2 py-1 rounded uppercase">${doc.type || 'FILE'}</span></td>
            <td class="p-5 text-sm text-slate-500">${doc.date || '-'}</td>
            <td class="p-5 text-right"><button class="text-indigo-600 hover:text-indigo-800 text-sm font-medium">상세보기</button></td>
        `;
        tbody.appendChild(tr);
    });
}


/* =========================================
   5. 상세 패널 (Drawer) - 공통 사용
   ========================================= */
function openDocumentDetail(doc) {
    if (!doc) return;
    // ... (이전 코드와 동일, 요약 내용 없으면 AI 유도 멘트)
    const headerHtml = `
        <span class="inline-block px-2 py-1 rounded bg-slate-100 text-slate-500 text-xs font-bold mb-2 uppercase">${doc.type || 'FILE'}</span>
        <h2 class="text-2xl font-bold text-slate-900 leading-tight break-words">${doc.title}</h2>
        <p class="text-sm text-indigo-600 font-medium mt-1">${doc.vendor || "PBS Docs"}</p>
    `;
    document.getElementById('drawer-header').innerHTML = headerHtml;
    
    const summaryText = doc.summary && doc.summary.length > 20 
        ? doc.summary 
        : "이 문서의 AI 요약 정보가 아직 생성되지 않았습니다.<br>AI 어시스턴트에게 요약을 요청해보세요.";
    document.getElementById('drawer-summary').innerHTML = summaryText;

    document.getElementById('drawer-keypoints').innerHTML = '<li class="text-slate-400 text-sm">분석 데이터가 없습니다.</li>';
    document.getElementById('drawer-author').innerText = "Admin";
    document.getElementById('drawer-date').innerText = doc.date || "Unknown";

    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('doc-drawer');
    backdrop.classList.remove('hidden');
    setTimeout(() => {
        backdrop.classList.remove('opacity-0');
        drawer.classList.remove('translate-x-full');
    }, 10);
}

function closeDocumentDetail() {
    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('doc-drawer');
    drawer.classList.add('translate-x-full');
    backdrop.classList.add('opacity-0');
    setTimeout(() => { backdrop.classList.add('hidden'); }, 300);
}