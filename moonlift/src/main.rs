mod cranelift_jit;
mod luajit;
mod runtime;

use runtime::Runtime;
use std::env;
use std::process::ExitCode;

fn usage() {
    eprintln!("usage: moonlift run <script.lua>");
}

fn main() -> ExitCode {
    let mut args = env::args();
    let _exe = args.next();
    let Some(cmd) = args.next() else {
        usage();
        return ExitCode::from(2);
    };

    match cmd.as_str() {
        "run" => {
            let Some(path) = args.next() else {
                usage();
                return ExitCode::from(2);
            };
            if args.next().is_some() {
                usage();
                return ExitCode::from(2);
            }

            match Runtime::new().and_then(|mut rt| {
                rt.initialize()?;
                rt.run_file(&path)
            }) {
                Ok(()) => ExitCode::SUCCESS,
                Err(err) => {
                    eprintln!("moonlift: {}", err);
                    ExitCode::from(1)
                }
            }
        }
        _ => {
            usage();
            ExitCode::from(2)
        }
    }
}
