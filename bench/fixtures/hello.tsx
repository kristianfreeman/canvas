export default function Hello({ data }: { data?: { name?: string } }) {
  return (
    <div>
      <h1>Hello, {data?.name ?? 'Canvas'}</h1>
      <p>A plain component with no kit imports.</p>
    </div>
  )
}
