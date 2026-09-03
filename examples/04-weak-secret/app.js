async function ping() {
  const res = await fetch("https://api.example.com/health", {
    headers: { "X-Api-Key": process.env.API_KEY },
  });
  return res.ok;
}

export { ping };
