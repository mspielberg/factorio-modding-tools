#!/usr/bin/env python3
import argparse
import concurrent.futures
import json
import logging
import os
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

def get_factorio_home():
    platform_paths = {
        'darwin': os.path.expanduser('~/Library/Application Support/factorio'),
        'win32': os.path.expandvars('$APPDATA/factorio'),
    }
    if sys.platform in platform_paths:
        return platform_paths[sys.platform]
    return None

def get_player_data():
    with open(os.path.join(get_factorio_home(), 'player-data.json')) as player_data:
        return json.load(player_data)

def get_release(mod_name):
    url = f"https://mods.factorio.com/api/mods/{urllib.parse.quote(mod_name)}"
    with urllib.request.urlopen(url) as m:
        mod_info = json.load(m)
        return mod_info['releases'][-1]

def copyfileobj(fsrc, fdst, length=16*1024):
    total_size = 0
    while 1:
        buf = fsrc.read(length)
        if not buf:
            break
        total_size += fdst.write(buf)
    return total_size

def download_mod(player_data, moddir, mod_name):
    release = get_release(mod_name)
    output_name = f"{mod_name}_{release['version']}.zip"
    output_path = os.path.join(moddir, output_name)

    if os.access(output_path, os.F_OK):
        logging.info(f"{output_name} already present")
        return { 'size_in_b': 0, 'elapsed_in_s': 0 }
    
    params = urllib.parse.urlencode({
        'username': player_data['service-username'],
        'token': player_data['service-token'],
    })
    download_url = f"https://mods.factorio.com{release['download_url']}?{params}"
    logging.info(f"Downloading {mod_name}")
    start = time.time_ns()
    total_size = 0
    req = urllib.request.Request(download_url)
    req.add_header('User-Agent', 'factorio-mod-downloader/0.1.0')
    with urllib.request.urlopen(req) as response:
        if not 200 <= response.getcode() < 300 or response.getheader('Content-Type') != 'application/zip':
            raise 'failed'
            raise urllib.error.HTTPError(download_url, response.getcode(), response.msg, response.headers, response)
        with open(output_path, 'wb') as f:
            total_size = copyfileobj(response, f)
    end = time.time_ns()
    elapsed_s = (end-start) / 1e9
    logging.info(f"Downloaded {mod_name} ({total_size // 1024} KiB in {round(elapsed_s, 1)} s; {round(total_size / 1024 / elapsed_s, 1)} KiB/s)")
    return {
        'size_in_b': total_size,
        'elapsed_in_s': elapsed_s,
    }

def download_mods(player_data, moddir, mod_names):
    total_size = 0
    start = time.time_ns()
    with concurrent.futures.ThreadPoolExecutor() as executor:
        futures = [executor.submit(download_mod, player_data, moddir, mod_name) for mod_name in mod_names]
        for result in concurrent.futures.as_completed(futures):
            total_size += result.result()['size_in_b']
    end = time.time_ns()
    elapsed_s = (end-start) / 1e9
    speed_bps = total_size / elapsed_s
    logging.info(f"Downloaded {len(mod_names)} mods ({total_size // 1024} KiB in {round(elapsed_s, 1)} s; {round(speed_bps / 1024, 1)} KiB/s)")

def parse_mod_list(f):
    return [entry['name'] for entry in json.load(f)['mods'] if entry['enabled'] and entry['name'] != 'base']

def parse_args():
    def csv(arg):
        return arg.split(',')
    parser = argparse.ArgumentParser(
        description="""Download the latest versions of Factorio mods from the portal""",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument(
        '--factorio-home',
        metavar='PATH',
        help='path to directory containing player-data.json',
        default=get_factorio_home(),
        required=(get_factorio_home() is None))
    parser.add_argument('--outdir', default='.')
    inputs_group = parser.add_mutually_exclusive_group(required=True)
    inputs_group.add_argument('--mod-list', metavar='PATH_TO_MOD_LIST', type=open)
    inputs_group.add_argument('--mods', metavar='MOD,MOD,...', type=csv)
    return parser.parse_args()

def main():
    logging.basicConfig(level = logging.INFO)
    args = parse_args()
    mod_names = args.mods if args.mods is not None else parse_mod_list(args.mod_list)
    download_mods(get_player_data(), args.outdir, mod_names)

if __name__ == '__main__':
    main()