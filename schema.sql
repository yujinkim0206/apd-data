-- ------------------------------------------------------------
-- 1. Account
-- 인증/계정 정보. 서비스 전체 최상위 엔티티.
-- ------------------------------------------------------------
CREATE TABLE account (
    user_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uoft_email      VARCHAR(255) NOT NULL UNIQUE
        CHECK (uoft_email LIKE '%@mail.utoronto.ca'),
    email_verified  BOOLEAN NOT NULL DEFAULT FALSE,
    password_hash   VARCHAR(255) NOT NULL,
    display_name    VARCHAR(100) NOT NULL,                  -- 실명 아니어도 됨
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    account_status  VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (account_status IN ('active', 'suspended', 'deleted'))
);

-- ------------------------------------------------------------
-- 2. Profile
-- 기본 프로필 정보. Account와 1:1.
-- ------------------------------------------------------------
CREATE TABLE profile (
    user_id          UUID PRIMARY KEY
        REFERENCES account(user_id) ON DELETE CASCADE,
    profile_picture  VARCHAR(500),                          -- 미등록 시 기본이미지
    campus           VARCHAR(20)
        CHECK (campus IN ('St.George', 'UTM', 'UTSC')),
    year             INT
        CHECK (year IN (1, 2, 3, 4)),                       -- 4 = 4+
    gender           VARCHAR(30),
    nationality      VARCHAR(100),
    about            TEXT
);

-- ------------------------------------------------------------
-- 3. MentoringPreference
-- 멘토링 참여 설정. Account와 1:1.
-- ------------------------------------------------------------
CREATE TABLE mentoring_preference (
    user_id            UUID PRIMARY KEY
        REFERENCES account(user_id) ON DELETE CASCADE,
    mentoring_opt_in   BOOLEAN NOT NULL DEFAULT FALSE,
    availability       VARCHAR(20) NOT NULL DEFAULT 'Available'
        CHECK (availability IN ('Available', 'Busy', 'Hidden'))
);

-- ------------------------------------------------------------
-- 3b. UserTopic
-- I Can Offer / I'm Looking For 다중선택 junction table.
-- ------------------------------------------------------------
CREATE TABLE user_topic (
    topic_id    BIGSERIAL PRIMARY KEY,
    user_id     UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    role        VARCHAR(20) NOT NULL
        CHECK (role IN ('offer', 'looking_for')),
    topic       VARCHAR(50) NOT NULL
        CHECK (topic IN (
            'Course Selection',
            'Program & Degree Requirements',
            'Study Tips & GPA Management',
            'First-year Adjustment',
            'Clubs & Campus Life',
            'Study Buddy'
        )),
    UNIQUE (user_id, role, topic)
);

-- ------------------------------------------------------------
-- 4. ContactMethod
-- 사용자가 등록 가능한 연락 수단 (복수 등록 가능).
-- ------------------------------------------------------------
CREATE TABLE contact_method (
    contact_id   BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    method_type  VARCHAR(20) NOT NULL
        CHECK (method_type IN ('Email', 'LinkedIn', 'KakaoTalk', 'Instagram', 'Other')),
    value        VARCHAR(255) NOT NULL
);

-- ------------------------------------------------------------
-- 5. Course
-- 과목 마스터 데이터.
-- ------------------------------------------------------------
CREATE TABLE course (
    course_code              VARCHAR(20) PRIMARY KEY,        -- 예: CSC301H1
    course_name               VARCHAR(255) NOT NULL,
    description                TEXT NOT NULL,
    prerequisite_text          TEXT,
    prerequisite_rule          JSONB,                        -- 원문 + 구조화 rule 분리
    corequisite_text           TEXT,
    corequisite_rule           JSONB,
    recommended_preparation    TEXT,                         -- 권장 선행학습 (필수 아님)
    exclusion_text             TEXT,
    exclusion_rule             JSONB,
    exclusion_note             TEXT,                         -- 조건부 설명
    enrolment_restriction      TEXT,
    campus                     VARCHAR(20) NOT NULL
        CHECK (campus IN ('St.George', 'UTM', 'UTSC')),
    course_level               INT NOT NULL,                 -- course_code에서 파생 (100/200/300/400)
    credit_value                DECIMAL(3,1) NOT NULL,        -- 0.5 / 1.0
    breadth_requirement         VARCHAR(255),
    term_offered                VARCHAR(10)
        CHECK (term_offered IN ('F', 'S', 'Y')),
    source_url                  VARCHAR(500) NOT NULL,
    last_reviewed                DATE NOT NULL
);

-- ------------------------------------------------------------
-- 6. Program
-- 프로그램(POSt) 마스터 데이터.
-- ------------------------------------------------------------
CREATE TABLE program (
    program_id                VARCHAR(20) PRIMARY KEY,       -- POSt 코드, 예: ASMAJ1689
    program_name              VARCHAR(255) NOT NULL,
    program_type              VARCHAR(20) NOT NULL
        CHECK (program_type IN ('Specialist', 'Major', 'Minor', 'Focus')),
    campus                    VARCHAR(20) NOT NULL
        CHECK (campus IN ('St.George', 'UTM', 'UTSC')),
    entry_requirement_text    TEXT,
    entry_requirement_rule    JSONB,                         -- admission category별 조건 (임시)
    source_url                VARCHAR(500) NOT NULL,
    last_reviewed              DATE NOT NULL
);

-- ------------------------------------------------------------
-- 7. ProgramExclusion
-- 프로그램 간 동시 이수 불가 규칙.
-- ------------------------------------------------------------
CREATE TABLE program_exclusion (
    id                    BIGSERIAL PRIMARY KEY,
    program_id            VARCHAR(20) NOT NULL
        REFERENCES program(program_id) ON DELETE CASCADE,
    excluded_program_id   VARCHAR(20) NOT NULL
        REFERENCES program(program_id) ON DELETE CASCADE,
    note                  TEXT,
    CHECK (program_id <> excluded_program_id),
    UNIQUE (program_id, excluded_program_id)
);

-- ------------------------------------------------------------
-- 8. Requirement
-- 졸업/프로그램 요건. self-referencing tree 구조 (parent-child).
-- 이유: Req2: "At least 1 Requirement from Req3 or Req4 or Req5 or Req6 or Req7"
-- ------------------------------------------------------------
CREATE TABLE requirement (
    requirement_id          BIGSERIAL PRIMARY KEY,
    level_type               VARCHAR(20) NOT NULL
        CHECK (level_type IN ('degree', 'program')),
    program_id                VARCHAR(20)
        REFERENCES program(program_id) ON DELETE CASCADE,     -- degree-level이면 NULL
    parent_requirement_id     BIGINT
        REFERENCES requirement(requirement_id) ON DELETE CASCADE,
    requirement_number        VARCHAR(20),                    -- Degree Explorer Req 번호 (추적용)
    description_text          TEXT NOT NULL,
    logic_type                 VARCHAR(30) NOT NULL
        CHECK (logic_type IN ('AND', 'OR', 'ALL_OF', 'AT_LEAST_N_CREDIT')),
    required_credit             DECIMAL(4,1),
    min_credit                  DECIMAL(4,1),                 -- 그룹 내 최소 크레딧
    max_credit                  DECIMAL(4,1),                 -- 그룹 내 최대 크레딧
    year_stage                  INT
        CHECK (year_stage IN (1, 2, 3, 4)),
    group_label                  VARCHAR(10),                  -- 예: A / B / C
    note                         TEXT,                          -- 각주/예외 설명
    is_leaf                      BOOLEAN NOT NULL DEFAULT TRUE, -- Program Progress 계산용
    source_url                   VARCHAR(500) NOT NULL,
    last_reviewed                 DATE NOT NULL,
    CHECK (level_type = 'degree' OR program_id IS NOT NULL)
);

-- ------------------------------------------------------------
-- 9. RequirementItem
-- Requirement를 구성하는 개별 과목 또는 하위 요건 참조.
-- ------------------------------------------------------------
CREATE TABLE requirement_item (
    id                       BIGSERIAL PRIMARY KEY,
    requirement_id            BIGINT NOT NULL
        REFERENCES requirement(requirement_id) ON DELETE CASCADE,
    course_code                VARCHAR(20)
        REFERENCES course(course_code) ON DELETE CASCADE,
    child_requirement_id        BIGINT
        REFERENCES requirement(requirement_id) ON DELETE CASCADE,
    CHECK (
        (course_code IS NOT NULL AND child_requirement_id IS NULL)
        OR (course_code IS NULL AND child_requirement_id IS NOT NULL)
    )  -- course_code 또는 child_requirement_id 중 하나만
);

-- ------------------------------------------------------------
-- 10. UserProgram
-- 사용자가 선택한 프로그램. Double Major 지원.
-- ------------------------------------------------------------
CREATE TABLE user_program (
    id           BIGSERIAL PRIMARY KEY,
    user_id      UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    program_id   VARCHAR(20) NOT NULL
        REFERENCES program(program_id) ON DELETE CASCADE,
    opted_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, program_id)
);

-- ------------------------------------------------------------
-- 11. UserCourseStatus
-- Academic History + Degree Path Plan + 엔진계산 결과 통합.
-- ------------------------------------------------------------
CREATE TABLE user_course_status (
    id                          BIGSERIAL PRIMARY KEY,
    user_id                     UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    course_code                 VARCHAR(20) NOT NULL
        REFERENCES course(course_code) ON DELETE CASCADE,
    status                       VARCHAR(20) NOT NULL
        CHECK (status IN (
            'Completed', 'In Progress', 'Planned', 'Interested',
            'Available', 'Locked', 'Excluded', 'Review Required'
        )),
    source                        VARCHAR(20) NOT NULL
        CHECK (source IN ('user_input', 'engine_calculated')),
    term_taken                    VARCHAR(20),                 -- 예: Winter 2026
    grade                          INT
        CHECK (grade >= 0 AND grade <= 100),
    is_visible                     BOOLEAN DEFAULT TRUE,       -- 멘토 프로필 공개 여부
    missing_requirement_note       TEXT,                        -- Locked 상태 부족 요건 설명
    updated_at                     TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, course_code)                              -- 동일 과목 중복 등록 불가
);

-- ------------------------------------------------------------
-- 12. Request
-- 멘토링 연결 요청.
-- ------------------------------------------------------------
CREATE TABLE request (
    request_id       BIGSERIAL PRIMARY KEY,
    requester_id       UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    mentor_id            UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    topic                  VARCHAR(50) NOT NULL,               -- mentor의 I Can Offer 중 선택
    related_course          VARCHAR(20) NOT NULL
        REFERENCES course(course_code),
    message                  TEXT NOT NULL,
    request_status             VARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (request_status IN ('Pending', 'Accepted', 'Declined')),
    reply_message                TEXT,                          -- Accept 시 선택
    contact_shared                 BIGINT[],                     -- 공개된 contact_id 배열
    created_at                     TIMESTAMP NOT NULL DEFAULT NOW(),
    responded_at                    TIMESTAMP,
    CHECK (requester_id <> mentor_id)                          -- 자기 자신에게 요청 불가
);

-- 동일 (requester_id, mentor_id) 조합에 Pending 요청 중복 방지
CREATE UNIQUE INDEX uq_request_pending
    ON request (requester_id, mentor_id)
    WHERE request_status = 'Pending';

-- -- ------------------------------------------------------------
-- -- 13. FeedbackReport
-- -- Footer의 Feedback & Report 컴포넌트.
-- -- ------------------------------------------------------------
-- CREATE TABLE feedback_report (
--     feedback_id    BIGSERIAL PRIMARY KEY,
--     user_id         UUID
--         REFERENCES account(user_id) ON DELETE SET NULL,        -- 비로그인 제보 가능 시 NULL
--     type              VARCHAR(20) NOT NULL
--         CHECK (type IN ('bug', 'feedback', 'report')),
--     target_type        VARCHAR(50),                             -- course / program / mentor_profile 등
--     target_id            VARCHAR(50),
--     content                TEXT NOT NULL,
--     status                  VARCHAR(20) NOT NULL DEFAULT 'open'
--         CHECK (status IN ('open', 'in_review', 'resolved')),
--     created_at              TIMESTAMP NOT NULL DEFAULT NOW()
-- );

-- ------------------------------------------------------------
-- 14. EventLog
-- WADU / Activation / Return Visit Rate 계산용 행동 로그.
-- ------------------------------------------------------------
CREATE TABLE event_log (
    event_id     BIGSERIAL PRIMARY KEY,
    user_id       UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    event_type     VARCHAR(50) NOT NULL,                        -- login / degree_path_view / mentor_search 등
    metadata          JSONB,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 15. DataSourceMap
-- 공식 출처 URL / 파싱 방식 / 갱신 주기 관리.
-- ------------------------------------------------------------
CREATE TABLE data_source_map (
    id               BIGSERIAL PRIMARY KEY,
    entity_name        VARCHAR(50) NOT NULL,                     -- Course / Program / Requirement
    attribute_name       VARCHAR(50) NOT NULL,
    source_url             VARCHAR(500) NOT NULL,
    access_method             VARCHAR(20) NOT NULL
        CHECK (access_method IN ('automated', 'manual')),
    update_cycle                VARCHAR(20) NOT NULL,             -- 예: 1년
    UNIQUE (entity_name, attribute_name)
);

-- ------------------------------------------------------------
-- 16. TranscriptUpload
-- Transcript 업로드 원본 파일 및 파싱 상태 관리.
-- ------------------------------------------------------------
CREATE TABLE transcript_upload (
    upload_id       BIGSERIAL PRIMARY KEY,
    user_id         UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    file_url        VARCHAR(500) NOT NULL,                      -- 저장된 원본 파일 위치
    parsed_status   VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (parsed_status IN ('pending', 'processing', 'success', 'failed')),
    error_note      TEXT,                                        -- 파싱 실패 시 사유
    uploaded_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    parsed_at       TIMESTAMP                                    -- 파싱 완료 시각
);

-- ------------------------------------------------------------
-- Indexes (조회 성능용 — 필요 시 조정)
-- ------------------------------------------------------------
CREATE INDEX idx_profile_gender ON profile(gender);
CREATE INDEX idx_requirement_program ON requirement(program_id);
CREATE INDEX idx_requirement_parent ON requirement(parent_requirement_id);
CREATE INDEX idx_requirement_item_requirement ON requirement_item(requirement_id);
CREATE INDEX idx_user_course_status_user ON user_course_status(user_id);
CREATE INDEX idx_user_program_user ON user_program(user_id);
CREATE INDEX idx_request_requester ON request(requester_id);
CREATE INDEX idx_request_mentor ON request(mentor_id);
CREATE INDEX idx_event_log_user ON event_log(user_id);
CREATE INDEX idx_event_log_type ON event_log(event_type);
CREATE INDEX idx_transcript_upload_user ON transcript_upload(user_id);