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
    first_name      VARCHAR(50) NOT NULL,                    -- 실명
    last_name       VARCHAR(50) NOT NULL,                    -- 실명
    created_at      TIMESTAMP NOT NULL DEFAULT NOW(),
    account_status  VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (account_status IN ('active', 'suspended', 'deleted'))
);

-- ------------------------------------------------------------
-- 2. Profile
-- 기본 프로필 정보. Account와 1:1.
-- ------------------------------------------------------------
CREATE TABLE profile (
    user_id               UUID PRIMARY KEY
        REFERENCES account(user_id) ON DELETE CASCADE,
    profile_picture       VARCHAR(500),                      -- 미등록 시 기본이미지
    campus                VARCHAR(20)
        CHECK (campus IN ('St.George', 'UTM', 'UTSC')),
    faculty                VARCHAR(50),
    degree_structure        VARCHAR(20)
        CHECK (degree_structure IN ('Specialist', 'Major', 'Minor')),
    year                    VARCHAR(5)
        CHECK (year IN ('1', '2', '3', '4', '4+')),
    gender                    VARCHAR(30)
        CHECK (gender IN ('Male', 'Female', 'Non-binary', 'Self-describe', 'Prefer not to say')),
    gender_self_describe        VARCHAR(30),                  -- gender = 'Self-describe'일 때만 사용
    nationality                    VARCHAR(100),
    about                             VARCHAR(500)
);

-- ------------------------------------------------------------
-- 3. MentoringPreference
-- 멘토링 참여 설정. Account와 1:1.
-- ------------------------------------------------------------
CREATE TABLE mentoring_preference (
    user_id                              UUID PRIMARY KEY
        REFERENCES account(user_id) ON DELETE CASCADE,
    mentoring_opt_in                       BOOLEAN NOT NULL DEFAULT FALSE,   -- 멘토로 참여 및 검색 노출 여부
    accepting_new_requests                   BOOLEAN NOT NULL DEFAULT TRUE,  -- 새 mentoring request 수신 여부
    academic_history_mentoring_consent         BOOLEAN NOT NULL DEFAULT TRUE -- Completed Courses를 course 기반 매칭에 활용 동의 여부
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
            'Clubs & Campus Life'
        )),
    UNIQUE (user_id, role, topic)
);

-- ------------------------------------------------------------
-- 4. ContactMethod
-- 사용자가 등록 가능한 연락 수단 (복수 등록 가능).
-- ------------------------------------------------------------
CREATE TABLE contact_method (
    contact_id                BIGSERIAL PRIMARY KEY,
    user_id                     UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    method_type                   VARCHAR(20) NOT NULL
        CHECK (method_type IN ('Email', 'LinkedIn', 'KakaoTalk', 'Instagram', 'Other')),
    value                           VARCHAR(255) NOT NULL,
    is_shared_for_mentoring          BOOLEAN NOT NULL DEFAULT FALSE  -- Accepted 시 이 연락처를 공유할지 여부
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
    program_id      VARCHAR(20) PRIMARY KEY,        -- 예: ASMAJ1689
    program_name    VARCHAR(255) NOT NULL,
    program_type    VARCHAR(20) NOT NULL
        CHECK (program_type IN ('Specialist', 'Major', 'Minor', 'Focus')),
    campus          VARCHAR(20) NOT NULL
        CHECK (campus IN ('St.George', 'UTM', 'UTSC')),
    source_url      VARCHAR(500) NOT NULL,
    last_reviewed   DATE NOT NULL
);

-- ------------------------------------------------------------
-- 6b. ProgramArea
-- Program Area Section 태그 (예: Computer Science, Data Science).
-- ------------------------------------------------------------
CREATE TABLE program_area (
    id           BIGSERIAL PRIMARY KEY,
    program_id   VARCHAR(20) NOT NULL
        REFERENCES program(program_id) ON DELETE CASCADE,
    area_name    VARCHAR(100) NOT NULL,                            -- 예: Computer Science, Data Science
    UNIQUE (program_id, area_name)
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
    CHECK (program_id <> excluded_program_id),
    UNIQUE (program_id, excluded_program_id)
);

-- ------------------------------------------------------------
-- 8. Requirement
-- 졸업/프로그램 요건. self-referencing tree 구조 (parent-child).
-- ------------------------------------------------------------
CREATE TABLE requirement (
    requirement_id         BIGSERIAL PRIMARY KEY,
    program_id              VARCHAR(20)
        REFERENCES program(program_id) ON DELETE CASCADE,   -- NULL이면 Degree 전체 요건 (예: ASPRGHBSC)
    parent_requirement_id    BIGINT
        REFERENCES requirement(requirement_id) ON DELETE CASCADE,  -- "in Req3" 같은 상위 요건 참조
    requirement_number       VARCHAR(20) NOT NULL,              -- Req1, Req2 ...
    description_text          TEXT NOT NULL,                     -- Degree Explorer 문구 그대로
    logic_type                 VARCHAR(30) NOT NULL
        CHECK (logic_type IN ('AND', 'OR', 'AT_LEAST_N_CREDIT', 'AT_MOST_N_CREDIT', 'MIN_CGPA')),
    required_credit             DECIMAL(4,1),                     -- "At least 20.0 Credits"의 20.0
    min_cgpa                     DECIMAL(3,2),                     -- "Minimum CGPA of 1.85"
    course_group_code             VARCHAR(100),                    -- AS-UNIVCRS / AS-200+ / CSC_BCB_MAJ_SPEC 등
    is_informational               BOOLEAN NOT NULL DEFAULT FALSE  -- "Note" 타입 (진행률 계산 제외)
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
    )
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
    user_status                  VARCHAR(20) NOT NULL
        CHECK (user_status IN ('Completed', 'In Progress', 'Planned', 'Interested')),
    course_availability            VARCHAR(20)
        CHECK (course_availability IN ('Available', 'Locked', 'Excluded', 'Review Required')),
    source                        VARCHAR(20) NOT NULL
        CHECK (source IN ('user_input', 'engine_calculated', 'transcript_import')),
    term_taken                    VARCHAR(20),                 -- 예: Winter 2026
    grade                          INT
        CHECK (grade >= 0 AND grade <= 100),
    available_for_mentoring        BOOLEAN NOT NULL DEFAULT TRUE, -- 이 과목을 mentor matching에 노출할지 (Completed 기본 TRUE)
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
    message                  VARCHAR(500),                     -- optional, max 500자
    request_status             VARCHAR(20) NOT NULL DEFAULT 'Pending'
        CHECK (request_status IN ('Pending', 'Accepted', 'Declined')),
    created_at                     TIMESTAMP NOT NULL DEFAULT NOW(),
    responded_at                    TIMESTAMP,
    CHECK (requester_id <> mentor_id)
);

-- ------------------------------------------------------------
-- 12b. RequestTopic
-- Request 전송 시 mentor의 I Can Offer 중 선택한 topic (다중선택 지원).
-- ------------------------------------------------------------
CREATE TABLE request_topic (
    id            BIGSERIAL PRIMARY KEY,
    request_id      BIGINT NOT NULL
        REFERENCES request(request_id) ON DELETE CASCADE,
    topic             VARCHAR(50) NOT NULL
        CHECK (topic IN (
            'Course Selection',
            'Program & Degree Requirements',
            'Study Tips & GPA Management',
            'First-year Adjustment',
            'Clubs & Campus Life'
        )),
    UNIQUE (request_id, topic)
);

-- 참고: 동일 (requester_id, mentor_id) 조합에 대한 Pending 요청 중복 허용

-- 참고: Contact Sharing은 조회 시점에 
-- request.request_status = 'Accepted' AND contact_method.is_shared_for_mentoring = TRUE
-- 조건으로 mentor_id를 통해 join하여 동적으로 계산 (snapshot 저장 안 함 → 항상 최신 연락처 값 참조).

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
-- Success Criteria 문서의 핵심 성공 지표 계산용 이벤트 로그.
-- ------------------------------------------------------------
CREATE TABLE event_log (
    event_id     BIGSERIAL PRIMARY KEY,
    user_id       UUID NOT NULL
        REFERENCES account(user_id) ON DELETE CASCADE,
    event_type     VARCHAR(50) NOT NULL,                        -- signup_completed / degree_path_viewed / mentor_search 등 (Success Criteria 10번 참고)
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
-- Indexes (조회 성능용 — 필요 시 조정)
-- ------------------------------------------------------------
CREATE INDEX idx_profile_gender ON profile(gender);
CREATE INDEX idx_program_area_program ON program_area(program_id);
CREATE INDEX idx_requirement_program ON requirement(program_id);
CREATE INDEX idx_requirement_parent ON requirement(parent_requirement_id);
CREATE INDEX idx_requirement_item_requirement ON requirement_item(requirement_id);
CREATE INDEX idx_user_course_status_user ON user_course_status(user_id);
CREATE INDEX idx_user_program_user ON user_program(user_id);
CREATE INDEX idx_request_requester ON request(requester_id);
CREATE INDEX idx_request_mentor ON request(mentor_id);
CREATE INDEX idx_request_topic_request ON request_topic(request_id);
CREATE INDEX idx_contact_method_user ON contact_method(user_id);
CREATE INDEX idx_event_log_user ON event_log(user_id);
CREATE INDEX idx_event_log_type ON event_log(event_type);