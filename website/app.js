// app.js

/* =========================================
   1. Mock Data (데이터 베이스 시뮬레이션)
   ========================================= */
/**
 * [TODO: 백엔드 개발자 참고]
 * 실제 배포 시 이 부분은 API 호출로 대체되어야 합니다.
 * 현재는 요약(summary)과 중요 내용(keyPoints)이 포함된 더미 데이터입니다.
 */
const MOCK_DB = [
    { 
        id: 1, 
        title: "RedHat OpenShift 설치 가이드 v4.12", 
        type: "pdf", 
        date: "2024-12-01", 
        vendor: "RedHat",
        author: "Infra Team",
        summary: "이 문서는 베어메탈 및 AWS 환경에서 OpenShift 4.12 클러스터를 구축하는 단계별 절차를 다룹니다. IPI(Installer Provisioned Infrastructure) 방식을 중점적으로 설명하며, 사전 요구사항 검증 스크립트가 포함되어 있습니다.",
        keyPoints: [
            "설치 전 DNS 레코드(API, Ingress) 설정 필수",
            "부트스트랩 노드는 설치 완료 후 제거 가능",
            "Control Plane 노드는 최소 3대 이상 구성 권장"
        ]
    },
    { 
        id: 2, 
        title: "AWS EKS 보안 모범 사례", 
        type: "docx", 
        date: "2025-01-05", 
        vendor: "AWS",
        author: "Security Part",
        summary: "Amazon EKS 운영 시 준수해야 할 보안 규정 및 IAM 역할(Role) 분리 전략을 설명합니다. 퍼블릭 액세스 차단 및 VPC CNI 플러그인 보안 설정이 주된 내용입니다.",
        keyPoints: [
            "Cluster Endpoint는 가급적 Private으로 설정",
            "IRSA(IAM Roles for Service Accounts) 적용 필수",
            "컨테이너 이미지는 ECR 스캔 활성화 권장"
        ]
    },
    { 
        id: 3, 
        title: "Google Cloud Anthos 배포 메뉴얼", 
        type: "pdf", 
        date: "2024-11-20", 
        vendor: "Google",
        author: "Cloud Ops",
        summary: "멀티 클라우드 환경에서 Anthos를 활용하여 하이브리드 클러스터를 관리하는 방법을 기술합니다. 온프레미스 GKE(Google Kubernetes Engine) 연결 방식이 포함되어 있습니다.",
        keyPoints: [
            "Anthos Config Management를 통한 정책 통합 관리",
            "Service Mesh(Istio) 기본 아키텍처 이해 필요",
            "Connect Gateway를 이용한 중앙 제어"
        ]
    },
    { 
        id: 4, 
        title: "VMware Tanzu 운영 가이드", 
        type: "html", 
        date: "2024-10-15", 
        vendor: "VMware", 
        author: "Platform Team",
        summary: "vSphere 환경 위에서 Tanzu Kubernetes Grid(TKG)를 운영하는 가이드입니다. 워크로드 클러스터 생성 및 라이프사이클 관리를 다룹니다.",
        keyPoints: [
            "Management Cluster와 Workload Cluster의 분리",
            "Tanzu CLI를 이용한 패키지 배포 방법",
            "Prometheus/Grafana 모니터링 연동"
        ]
    },
    { 
        id: 5, 
        title: "사내망 VPN 접속 트러블슈팅", 
        type: "txt", 
        date: "2025-01-02", 
        vendor: "Internal",
        author: "NetOps",
        summary: "재택근무 시 사내망 접속이 불안정할 때 확인해야 할 체크리스트입니다. 클라이언트 버전 호환성 및 라우팅 테이블 초기화 방법을 안내합니다.",
        keyPoints: [
            "GlobalProtect 클라이언트 최신 버전 확인",
            "PC 재부팅 후 라우팅 테이블 자동 갱신 확인",
            "MFA 인증 타임아웃 주의"
        ]
    }
];

/* =========================================
   2. 검색 및 AI 로직 (백엔드 시뮬레이션)
   ========================================= */

// 검색 함수
async function searchDocs(query) {
    console.log(`[System] Searching DB for: ${query}...`);
    
    // API 호출 지연 시뮬레이션 (0.5초)
    await new Promise(resolve => setTimeout(resolve, 500));

    if (!query) return MOCK_DB;
    
    return MOCK_DB.filter(doc => 
        doc.title.toLowerCase().includes(query.toLowerCase()) || 
        doc.vendor.toLowerCase().includes(query.toLowerCase())
    );
}

// AI 챗봇 함수
async function askAI(userMessage) {
    console.log(`[System] Sending prompt to AI: ${userMessage}`);

    // AI 생각하는 시간 시뮬레이션 (1.5초)
    await new Promise(resolve => setTimeout(resolve, 1500));

    let aiResponse = "";
    let relatedDocs = [];

    if (userMessage.includes("OpenShift") || userMessage.includes("설명서")) {
        aiResponse = `
            <strong>Red Hat OpenShift</strong>에 대한 문서를 찾아보았습니다.<br><br>
            OpenShift는 쿠버네티스 기반의 엔터프라이즈 컨테이너 플랫폼입니다. 
            주요 설치 방식은 IPI(Installer Provisioned Infrastructure)와 UPI가 있으며, 
            제공된 문서에서 v4.12 설치 가이드를 확인하실 수 있습니다.
        `;
        relatedDocs = [MOCK_DB[0]]; 
    } else {
        aiResponse = `
            질문하신 <strong>"${userMessage}"</strong>에 대한 내용을 내부 기술 문서에서 검색했습니다.<br><br>
            관련된 벤더사의 문서를 우측 패널에서 확인해 주세요. 
            추가적으로 요약이 필요하시면 '이 문서 요약해줘'라고 말씀해 주세요.
        `;
        relatedDocs = [MOCK_DB[1], MOCK_DB[4]]; 
    }

    return { text: aiResponse, sources: relatedDocs };
}

/* =========================================
   3. UI 동작 로직
   ========================================= */

// 엔터키 감지
function handleEnter(event, callback) {
    if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        callback();
    }
}

// [index.html] 메인 검색 실행
async function runMainSearch() {
    const input = document.getElementById('main-search-input');
    const query = input.value.trim();
    if(!query) return alert("검색어를 입력해주세요.");

    const resultArea = document.getElementById('search-results');
    const listContainer = document.getElementById('result-list');
    
    // 로딩 표시
    listContainer.innerHTML = '<div class="text-center p-4"><div class="loader mx-auto"></div></div>';
    resultArea.classList.remove('hidden');

    const results = await searchDocs(query);
    
    // 결과 렌더링
    listContainer.innerHTML = '';
    if(results.length === 0) {
        listContainer.innerHTML = '<p class="text-center text-slate-500 py-4">검색 결과가 없습니다.</p>';
    } else {
        results.forEach(doc => {
            const item = document.createElement('div');
            
            // [중요] 클릭 시 상세 패널 열기 (onclick)
            item.className = 'bg-white p-4 rounded-xl border border-slate-200 hover:shadow-md hover:border-indigo-300 transition cursor-pointer mb-3 fade-in group';
            item.onclick = () => openDocumentDetail(doc.id); 

            item.innerHTML = `
                <div class="flex items-center gap-4">
                    <div class="w-12 h-12 bg-slate-50 rounded-lg flex items-center justify-center text-slate-500 font-bold uppercase text-xs border border-slate-100 group-hover:bg-indigo-50 group-hover:text-indigo-600 transition">
                        ${doc.type}
                    </div>
                    <div class="flex-1">
                        <div class="flex justify-between items-start">
                            <h4 class="font-bold text-slate-800 group-hover:text-indigo-700 transition">${doc.title}</h4>
                            <span class="text-xs text-slate-400 bg-slate-50 px-2 py-1 rounded">${doc.vendor}</span>
                        </div>
                        <p class="text-xs text-slate-500 mt-1 line-clamp-1">${doc.summary ? doc.summary : '내용 미리보기 없음'}</p>
                    </div>
                </div>
            `;
            listContainer.appendChild(item);
        });
    }
}

/* =========================================
   4. 상세 패널 (Drawer) 로직
   ========================================= */

// 문서 상세 패널 열기
function openDocumentDetail(id) {
    const doc = MOCK_DB.find(d => d.id === id);
    if (!doc) return;

    // 헤더 주입
    const headerHtml = `
        <span class="inline-block px-2 py-1 rounded bg-slate-100 text-slate-500 text-xs font-bold mb-2 uppercase">${doc.type}</span>
        <h2 class="text-2xl font-bold text-slate-900 leading-tight">${doc.title}</h2>
        <p class="text-sm text-indigo-600 font-medium mt-1">${doc.vendor}</p>
    `;
    document.getElementById('drawer-header').innerHTML = headerHtml;

    // 요약 주입
    document.getElementById('drawer-summary').innerHTML = doc.summary || "AI 요약 정보가 없습니다.";

    // Key Points 주입
    const kpContainer = document.getElementById('drawer-keypoints');
    kpContainer.innerHTML = ''; 
    if (doc.keyPoints && doc.keyPoints.length > 0) {
        doc.keyPoints.forEach(point => {
            const li = document.createElement('li');
            li.className = "flex items-start gap-3 p-3 bg-slate-50 rounded-lg text-sm text-slate-700";
            li.innerHTML = `<i class="fas fa-dot-circle text-xs mt-1.5 text-slate-400"></i> <span>${point}</span>`;
            kpContainer.appendChild(li);
        });
    } else {
        kpContainer.innerHTML = '<li class="text-slate-400 text-sm">등록된 핵심 내용이 없습니다.</li>';
    }

    // 메타 정보 주입
    document.getElementById('drawer-author').innerText = doc.author || "PBS Team";
    document.getElementById('drawer-date').innerText = doc.date;

    // 패널 열기 애니메이션
    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('doc-drawer');

    backdrop.classList.remove('hidden');
    setTimeout(() => {
        backdrop.classList.remove('opacity-0');
        drawer.classList.remove('translate-x-full');
    }, 10);
}

// 문서 상세 패널 닫기
function closeDocumentDetail() {
    const backdrop = document.getElementById('drawer-backdrop');
    const drawer = document.getElementById('doc-drawer');

    drawer.classList.add('translate-x-full');
    backdrop.classList.add('opacity-0');

    setTimeout(() => {
        backdrop.classList.add('hidden');
    }, 300); 
}

/* =========================================
   5. 채팅(Chat) 관련 로직
   ========================================= */

async function sendChatMessage() {
    const input = document.getElementById('chat-input');
    const container = document.getElementById('chat-container');
    const message = input.value.trim();

    if (!message) return;

    appendMessage('user', message);
    input.value = '';

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
    
    if (role === 'user') {
        div.classList.add('flex-row-reverse');
        div.innerHTML = `
            <div class="w-8 h-8 bg-slate-200 rounded-full flex items-center justify-center text-slate-600 flex-shrink-0 mt-1"><i class="fas fa-user text-sm"></i></div>
            <div class="bg-indigo-600 text-white p-4 rounded-2xl rounded-tr-none shadow-md max-w-2xl text-sm leading-relaxed">${text}</div>
        `;
    } else {
        div.innerHTML = `
            <div class="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-white flex-shrink-0 mt-1"><i class="fas fa-robot text-sm"></i></div>
            <div class="bg-white p-4 rounded-2xl rounded-tl-none shadow-sm border border-slate-100 max-w-2xl text-slate-700 text-sm leading-relaxed">${text}</div>
        `;
    }
    container.appendChild(div);
    container.scrollTop = container.scrollHeight;
}

// [app.js] 맨 아래에 있는 updateReferences 함수를 이걸로 덮어씌우세요.

function updateReferences(docs) {
    const container = document.getElementById('ref-container');
    container.innerHTML = ''; // 초기화
    
    docs.forEach(doc => {
        const div = document.createElement('div');
        
        // [수정된 부분] 클릭 시 상세 패널(Drawer) 열기 연결!
        div.className = "bg-white p-3 rounded-lg border border-slate-200 hover:border-indigo-300 cursor-pointer transition shadow-sm fade-in mb-3";
        div.onclick = () => openDocumentDetail(doc.id); 

        div.innerHTML = `
            <div class="flex items-center justify-between mb-1">
                <span class="text-xs font-bold text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded">${doc.vendor}</span>
                <span class="text-xs text-slate-400">${doc.type.toUpperCase()}</span>
            </div>
            <div class="text-sm font-bold text-slate-700 mb-1">${doc.title}</div>
            <div class="text-xs text-slate-500">AI 참조 확률: ${(Math.random() * 20 + 80).toFixed(0)}%</div>
        `;
        container.appendChild(div);
    });
}