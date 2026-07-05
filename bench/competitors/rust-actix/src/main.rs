use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer, Responder};
use regex::Regex;
use std::env;
use std::sync::LazyLock;
use std::time::{Duration, Instant};

static DEVICE_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9_-]{1,64}$").unwrap());
static FILE_PATTERN: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[a-z0-9_.-]{1,80}$").unwrap());

async fn ok() -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body("ok")
}

async fn meta() -> impl Responder {
    HttpResponse::Ok()
        .content_type("application/json")
        .body(r#"{"framework":"rust-actix","runtime":"rust","backend":"actix-web"}"#)
}

async fn typed_param(req: HttpRequest) -> impl Responder {
    let id = req.match_info().query("id");
    if id.parse::<u64>().is_err() {
        return HttpResponse::BadRequest().body("bad id");
    }
    HttpResponse::Ok()
        .content_type("application/json")
        .body(id.to_owned())
}

async fn device(req: HttpRequest) -> impl Responder {
    let id = req.match_info().query("device_id");
    if !DEVICE_PATTERN.is_match(id) {
        return HttpResponse::BadRequest().body("bad device id");
    }
    HttpResponse::Ok()
        .content_type("application/json")
        .body(id.to_owned())
}

async fn file(req: HttpRequest) -> impl Responder {
    let name = req.match_info().query("name");
    if !FILE_PATTERN.is_match(name) {
        return HttpResponse::BadRequest().body("bad file name");
    }
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body(name.to_owned())
}

async fn echo(body: web::Bytes) -> impl Responder {
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body(body)
}

fn cpu_duration(label: &str) -> Option<(Duration, &'static str)> {
    match label {
        "50us" => Some((Duration::from_micros(50), "50")),
        "100us" => Some((Duration::from_micros(100), "100")),
        "250us" => Some((Duration::from_micros(250), "250")),
        "500us" => Some((Duration::from_micros(500), "500")),
        "1ms" => Some((Duration::from_millis(1), "1000")),
        "2ms" => Some((Duration::from_millis(2), "2000")),
        "5ms" => Some((Duration::from_millis(5), "5000")),
        _ => None,
    }
}

fn sleep_duration(label: &str) -> Option<Duration> {
    match label {
        "1ms" => Some(Duration::from_millis(1)),
        "5ms" => Some(Duration::from_millis(5)),
        "10ms" => Some(Duration::from_millis(10)),
        _ => None,
    }
}

fn spin_for(duration: Duration) {
    let start = Instant::now();
    while start.elapsed() < duration {
        std::hint::spin_loop();
    }
}

async fn work_cpu(req: HttpRequest) -> impl Responder {
    let duration = req.match_info().query("duration");
    let Some((target, checksum)) = cpu_duration(duration) else {
        return HttpResponse::NotFound().body("not found");
    };
    spin_for(target);
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body(format!("work:cpu:{duration}:{checksum}"))
}

async fn work_sleep(req: HttpRequest) -> impl Responder {
    let duration = req.match_info().query("duration");
    let Some(target) = sleep_duration(duration) else {
        return HttpResponse::NotFound().body("not found");
    };
    actix_web::rt::time::sleep(target).await;
    HttpResponse::Ok()
        .content_type("text/plain; charset=utf-8")
        .body(format!("sleep:{duration}"))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let mut port = String::from("8080");
    for arg in env::args().skip(1) {
        if let Some(value) = arg.strip_prefix("--port=") {
            port = value.to_owned();
        }
    }
    let addr = format!("127.0.0.1:{port}");
    println!("Rust Actix listening on http://{addr}");
    HttpServer::new(|| {
        App::new()
            .route("/__bench/meta", web::get().to(meta))
            .route("/__bench/plain", web::get().to(ok))
            .route("/__bench/plain-static", web::get().to(ok))
            .route("/__bench/raw", web::get().to(ok))
            .route("/__bench/hybrid-zig", web::get().to(ok))
            .route("/__bench/hybrid-inline", web::get().to(ok))
            .route("/__bench/hybrid-inline-text-literal", web::get().to(ok))
            .route(
                "/__bench/hybrid-inline-params/{id}",
                web::get().to(typed_param),
            )
            .route("/__bench/hybrid-inline-echo", web::post().to(echo))
            .route("/__bench/work/cpu/{duration}", web::get().to(work_cpu))
            .route("/__bench/work/sleep/{duration}", web::get().to(work_sleep))
            .route("/health", web::get().to(ok))
            .route("/users/{id}", web::get().to(typed_param))
            .route("/devices/{device_id}", web::get().to(device))
            .route("/files/{name}", web::get().to(file))
            .route("/echo", web::post().to(echo))
            .route("/hybrid-inline", web::get().to(ok))
    })
    .bind(addr)?
    .run()
    .await
}
